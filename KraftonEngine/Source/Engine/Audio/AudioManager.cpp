#include "AudioManager.h"
#include "Core/Logging/Log.h"
#include "GameFramework/Camera/PlayerCameraManager.h"
#include "GameFramework/GameMode/PlayerController.h"
#include "GameFramework/World.h"
#include "Math/Rotator.h"
#include "Platform/Paths.h"
#include "Render/Types/MinimalViewInfo.h"
#include <algorithm>

namespace
{
	bool TryGetListenerPOV(UWorld* World, FMinimalViewInfo& OutPOV)
	{
		if (!World)
		{
			return false;
		}

		APlayerController* PlayerController = World->GetFirstPlayerController();
		if (!PlayerController)
		{
			return false;
		}

		APlayerCameraManager* CameraManager = PlayerController->GetPlayerCameraManager();
		if (!CameraManager)
		{
			return false;
		}

		if (CameraManager->GetCameraCachePOV(OutPOV))
		{
			return true;
		}

		return CameraManager->GetCameraView(OutPOV);
	}
}

bool FAudioManager::Initialize()
{
	if (FMOD::System_Create(&System) != FMOD_OK || !System)
	{
		UE_LOG("Failed to create FMOD system.");
		return false;
	}

	if (System->init(512, FMOD_INIT_NORMAL, nullptr) != FMOD_OK)
	{
		UE_LOG("Failed to initialize FMOD system.");
		Shutdown();
		return false;
	}

	System->getMasterChannelGroup(&MasterGroup);

	LoadDefaultAudios();

	return true;
}

void FAudioManager::Shutdown()
{
	if (!System)
	{
		MasterGroup = nullptr;
		BGMChannel = nullptr;
		LoopChannels.clear();
		Audios.clear();
		return;
	}

	StopBGM();
	StopAllLoops();
	if (MasterGroup)
	{
		MasterGroup->stop();
		MasterGroup = nullptr;
	}
	System->update();

	for (auto& Pair : Audios)
	{
		if (Pair.second.Sound)
		{
			Pair.second.Sound->release();
		}
	}
	Audios.clear();

	System->update();
	System->close();
	System->release();
	System = nullptr;
}

void FAudioManager::Tick()
{
	if (System)
	{
		System->update();
	}
}

FMOD_VECTOR FAudioManager::ToFmodVector(const FVector& Value)
{
	// Engine: +X forward, +Y right, +Z up (left-handed).
	// FMOD (left-handed): +X right, +Y up, +Z forward.
	FMOD_VECTOR Out{};
	Out.x = Value.Y;
	Out.y = Value.Z;
	Out.z = Value.X;
	return Out;
}

void FAudioManager::SetListener(const FVector& Position, const FVector& Forward, const FVector& Up)
{
	if (!System)
	{
		return;
	}

	const FMOD_VECTOR FmodPosition = ToFmodVector(Position);
	const FMOD_VECTOR FmodForward = ToFmodVector(Forward);
	const FMOD_VECTOR FmodUp = ToFmodVector(Up);
	const FMOD_VECTOR ZeroVelocity{0.0f, 0.0f, 0.0f};

	System->set3DListenerAttributes(0, &FmodPosition, &ZeroVelocity, &FmodForward, &FmodUp);
}

bool FAudioManager::UpdateListenerFromWorld(UWorld* World)
{
	FMinimalViewInfo POV;
	if (!TryGetListenerPOV(World, POV))
	{
		return false;
	}

	SetListener(POV.Location, POV.Rotation.GetForwardVector(), POV.Rotation.GetUpVector());
	return true;
}

FMOD::Sound* FAudioManager::FindSound(const FString& Key) const
{
	if (!Audios.contains(Key))
	{
		return nullptr;
	}

	return Audios.at(Key).Sound;
}

bool FAudioManager::LoadAudio(const FString& Key, const FString& Path, bool bLoop, bool b3D)
{
	if (!System || Key.empty() || Path.empty())
	{
		return false;
	}

	if (Audios.contains(Key))
	{
		FAudioSoundEntry& Existing = Audios[Key];
		if (Existing.Sound && Existing.Path == Path && Existing.bLoop == bLoop && Existing.b3D == b3D)
		{
			Existing.RefCount++;
			return true;
		}

		UE_LOG("[AudioManager] LoadAudio key collision with different settings. Key=%s", Key.c_str());
		return false;
	}

	FString FullPath = FPaths::ToUtf8(FPaths::Combine(FPaths::AudioDir(), FPaths::ToWide(Path)));

	FMOD::Sound* Sound = nullptr;
	FMOD_MODE Mode = FMOD_DEFAULT | (bLoop ? FMOD_LOOP_NORMAL : FMOD_LOOP_OFF);
	if (b3D)
	{
		Mode |= FMOD_3D;
	}

	if (System->createSound(FullPath.c_str(), Mode, nullptr, &Sound) != FMOD_OK)
	{
		return false;
	}

	FAudioSoundEntry Entry;
	Entry.Sound = Sound;
	Entry.RefCount = 1;
	Entry.bLoop = bLoop;
	Entry.b3D = b3D;
	Entry.Path = Path;
	Audios[Key] = Entry;
	return true;
}

void FAudioManager::ReleaseAudio(const FString& Key)
{
	if (!Audios.contains(Key))
	{
		return;
	}

	FAudioSoundEntry& Entry = Audios[Key];
	Entry.RefCount = std::max(0, Entry.RefCount - 1);
	if (Entry.RefCount > 0)
	{
		return;
	}

	if (Entry.Sound)
	{
		Entry.Sound->release();
	}
	Audios.erase(Key);
}

void FAudioManager::Apply3DSettingsToChannel(FMOD::Channel* Channel, const FAudio3DPlaySettings& Settings3D) const
{
	if (!Channel || !Settings3D.bEnabled)
	{
		return;
	}

	const FMOD_VECTOR Position = ToFmodVector(Settings3D.Position);
	const FMOD_VECTOR ZeroVelocity{0.0f, 0.0f, 0.0f};
	const float MinDistance = std::max(Settings3D.MinDistance, 0.0f);
	const float MaxDistance = std::max(Settings3D.MaxDistance, MinDistance);

	Channel->set3DAttributes(&Position, &ZeroVelocity);
	Channel->set3DMinMaxDistance(MinDistance, MaxDistance);
}

void FAudioManager::PlayAudio(const FString& Key, float Volume, float Pitch, const FAudio3DPlaySettings* Settings3D)
{
	FMOD::Sound* Sound = FindSound(Key);
	if (!System || !Sound)
	{
		return;
	}

	FMOD::Channel* Channel = nullptr;
	System->playSound(Sound, nullptr, false, &Channel);

	if (Channel)
	{
		Channel->setVolume(std::clamp(Volume, 0.0f, 1.0f));
		Channel->setPitch(std::clamp(Pitch, 0.1f, 3.0f));
		if (Settings3D)
		{
			Apply3DSettingsToChannel(Channel, *Settings3D);
		}
	}
}

void FAudioManager::PlayAudioFadeOut(const FString& Key, float Volume, float FadeOutSeconds, float Pitch, const FAudio3DPlaySettings* Settings3D)
{
	FMOD::Sound* Sound = FindSound(Key);
	if (!System || !Sound)
	{
		return;
	}

	FMOD::Channel* Channel = nullptr;
	System->playSound(Sound, nullptr, false, &Channel);

	if (!Channel)
	{
		return;
	}

	const float ClampedVolume = std::clamp(Volume, 0.0f, 1.0f);
	Channel->setVolume(ClampedVolume);
	Channel->setPitch(std::clamp(Pitch, 0.1f, 3.0f));
	if (Settings3D)
	{
		Apply3DSettingsToChannel(Channel, *Settings3D);
	}

	int SampleRate = 0;
	System->getSoftwareFormat(&SampleRate, nullptr, nullptr);
	if (SampleRate <= 0 || FadeOutSeconds <= 0.0f)
	{
		return;
	}

	unsigned long long DspClock = 0;
	unsigned long long ParentClock = 0;
	if (Channel->getDSPClock(&DspClock, &ParentClock) != FMOD_OK)
	{
		return;
	}

	const unsigned long long FadeDuration = static_cast<unsigned long long>(FadeOutSeconds * static_cast<float>(SampleRate));
	Channel->addFadePoint(ParentClock, ClampedVolume);
	Channel->addFadePoint(ParentClock + FadeDuration, 0.0f);
}

void FAudioManager::PlayBGM(const FString& Key, float Volume)
{
	FMOD::Sound* Sound = FindSound(Key);
	if (!System || !Sound)
	{
		return;
	}

	StopBGM();
	System->playSound(Sound, nullptr, false, &BGMChannel);

	if (BGMChannel)
	{
		BGMChannel->setVolume(Volume);
	}
}

void FAudioManager::StopBGM()
{
	if (BGMChannel)
	{
		BGMChannel->stop();
		BGMChannel = nullptr;
	}
}

void FAudioManager::PlayLoop(const FString& Key, const FString& LoopName, float Volume, float Pitch, const FAudio3DPlaySettings* Settings3D)
{
	FMOD::Sound* Sound = FindSound(Key);
	if (!System || !Sound || LoopName.empty())
	{
		return;
	}

	const bool bUse3D = Settings3D && Settings3D->bEnabled;
	if (FMOD::Channel* ExistingChannel = FindPlayingLoopChannel(LoopName))
	{
		ExistingChannel->setVolume(std::clamp(Volume, 0.0f, 1.0f));
		ExistingChannel->setPitch(std::clamp(Pitch, 0.1f, 3.0f));
		if (Settings3D)
		{
			Apply3DSettingsToChannel(ExistingChannel, *Settings3D);
		}
		return;
	}

	FMOD::Channel* Channel = nullptr;
	System->playSound(Sound, nullptr, false, &Channel);

	if (Channel)
	{
		Channel->setMode(FMOD_LOOP_NORMAL);
		Channel->setVolume(std::clamp(Volume, 0.0f, 1.0f));
		Channel->setPitch(std::clamp(Pitch, 0.1f, 3.0f));
		if (Settings3D)
		{
			Apply3DSettingsToChannel(Channel, *Settings3D);
		}

		FLoopChannelEntry& Entry = LoopChannels[LoopName];
		Entry.Channel = Channel;
		Entry.b3D = bUse3D;
	}
}

void FAudioManager::StopLoop(const FString& LoopName)
{
	if (!LoopChannels.contains(LoopName))
	{
		return;
	}

	if (LoopChannels[LoopName].Channel)
	{
		LoopChannels[LoopName].Channel->stop();
	}
	LoopChannels.erase(LoopName);
}

void FAudioManager::StopAllLoops()
{
	for (auto& Pair : LoopChannels)
	{
		if (Pair.second.Channel)
		{
			Pair.second.Channel->stop();
		}
	}
	LoopChannels.clear();
}

void FAudioManager::SetLoopVolume(const FString& LoopName, float Volume)
{
	if (FMOD::Channel* Channel = FindPlayingLoopChannel(LoopName))
	{
		Channel->setVolume(std::clamp(Volume, 0.0f, 1.0f));
	}
}

void FAudioManager::SetLoopPitch(const FString& LoopName, float Pitch)
{
	if (FMOD::Channel* Channel = FindPlayingLoopChannel(LoopName))
	{
		Channel->setPitch(std::clamp(Pitch, 0.1f, 3.0f));
	}
}

void FAudioManager::SetLoop3DAttributes(const FString& LoopName, const FVector& Position, float MinDistance, float MaxDistance)
{
	bool bIs3D = false;
	FMOD::Channel* Channel = FindPlayingLoopChannel(LoopName, &bIs3D);
	if (!Channel || !bIs3D)
	{
		return;
	}

	FAudio3DPlaySettings Settings3D;
	Settings3D.bEnabled = true;
	Settings3D.Position = Position;
	Settings3D.MinDistance = MinDistance;
	Settings3D.MaxDistance = MaxDistance;
	Apply3DSettingsToChannel(Channel, Settings3D);
}

bool FAudioManager::IsLoopPlaying(const FString& LoopName)
{
	return FindPlayingLoopChannel(LoopName) != nullptr;
}

FMOD::Channel* FAudioManager::FindPlayingLoopChannel(const FString& LoopName, bool* bOut3D)
{
	if (!LoopChannels.contains(LoopName))
	{
		return nullptr;
	}

	FLoopChannelEntry& Entry = LoopChannels[LoopName];
	FMOD::Channel* Channel = Entry.Channel;
	bool bIsPlaying = false;
	if (!Channel || Channel->isPlaying(&bIsPlaying) != FMOD_OK || !bIsPlaying)
	{
		LoopChannels.erase(LoopName);
		return nullptr;
	}

	if (bOut3D)
	{
		*bOut3D = Entry.b3D;
	}

	return Channel;
}

void FAudioManager::SetMasterVolume(float Volume)
{
	if (MasterGroup)
	{
		MasterGroup->setVolume(Volume);
	}
}

void FAudioManager::LoadDefaultAudios()
{
	LoadAudio("CameraShutter", "Camera/CameraShutter.mp3", false);
	LoadAudio("PhotoOut", "Camera/PhotoOut.mp3", false);
	LoadAudio("PistolFire", "Pistol/pistolFire.mp3", false);
	LoadAudio("Tinnitus", "Pistol/tinnitus.mp3", false);
}
