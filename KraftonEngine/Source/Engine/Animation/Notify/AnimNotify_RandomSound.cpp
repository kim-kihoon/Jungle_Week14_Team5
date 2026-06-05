#include "AnimNotify_RandomSound.h"

#include "Audio/AudioManager.h"
#include "Core/Logging/Log.h"

#include <random>

namespace
{
	static TSet<FString> GLoadedRandomSoundPaths;

	const FAnimNotifySoundEntry* PickRandomSoundEntry(const TArray<FAnimNotifySoundEntry>& Sounds)
	{
		TArray<const FAnimNotifySoundEntry*> Candidates;
		for (const FAnimNotifySoundEntry& Sound : Sounds)
		{
			if (!Sound.SoundPath.empty())
			{
				Candidates.push_back(&Sound);
			}
		}

		if (Candidates.empty())
		{
			return nullptr;
		}

		static std::mt19937 RNG{ std::random_device{}() };
		std::uniform_int_distribution<size_t> Dist(0, Candidates.size() - 1);
		return Candidates[Dist(RNG)];
	}

	FAnimNotifySoundEntry PickLegacyRandomSoundEntry(const TArray<FString>& SoundPaths, float Volume)
	{
		TArray<const FString*> Candidates;
		for (const FString& Path : SoundPaths)
		{
			if (!Path.empty())
			{
				Candidates.push_back(&Path);
			}
		}

		if (Candidates.empty())
		{
			return FAnimNotifySoundEntry();
		}

		static std::mt19937 RNG{ std::random_device{}() };
		std::uniform_int_distribution<size_t> Dist(0, Candidates.size() - 1);
		FAnimNotifySoundEntry Result;
		Result.SoundPath = *Candidates[Dist(RNG)];
		Result.Volume = Volume;
		Result.Pitch = 1.0f;
		return Result;
	}

	bool PlayRandomNotifySound(const FAnimNotifySoundEntry& Sound)
	{
		if (Sound.SoundPath.empty())
		{
			return false;
		}

		const FString Key = FString("AnimNotifyRandom:") + Sound.SoundPath;
		if (GLoadedRandomSoundPaths.find(Sound.SoundPath) == GLoadedRandomSoundPaths.end())
		{
			if (FAudioManager::Get().LoadAudio(Key, Sound.SoundPath, /*bLoop=*/false))
			{
				GLoadedRandomSoundPaths.insert(Sound.SoundPath);
			}
			else
			{
				UE_LOG("[AnimNotify_RandomSound] LoadAudio failed: %s", Sound.SoundPath.c_str());
				return false;
			}
		}

		FAudioManager::Get().PlayAudio(Key, Sound.Volume, Sound.Pitch);
		return true;
	}
}

void UAnimNotify_RandomSound::Notify(USkeletalMeshComponent* /*MeshComp*/, UAnimSequenceBase* /*Anim*/)
{
	const float TrackVolumeScale = GetDispatchVolumeScale();
	if (!Sounds.empty())
	{
		if (const FAnimNotifySoundEntry* Sound = PickRandomSoundEntry(Sounds))
		{
			FAnimNotifySoundEntry ScaledSound = *Sound;
			ScaledSound.Volume *= TrackVolumeScale;
			PlayRandomNotifySound(ScaledSound);
		}
		return;
	}

	FAnimNotifySoundEntry LegacySound = PickLegacyRandomSoundEntry(SoundPaths, Volume);
	LegacySound.Volume *= TrackVolumeScale;
	PlayRandomNotifySound(LegacySound);
}
