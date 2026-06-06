#include "GameFramework/Actor/AudioVolume.h"

#include "Audio/AudioManager.h"
#include "Component/Shape/BoxComponent.h"
#include "Core/Logging/Log.h"
#include "GameFramework/Pawn/Pawn.h"

#include <algorithm>
#include <cstdint>
#include <string>

namespace
{
	float Clamp01(float Value)
	{
		return std::max(0.0f, std::min(1.0f, Value));
	}
}

void AAudioVolume::BeginPlay()
{
	Super::BeginPlay();
}

void AAudioVolume::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);

	if (bPlaying)
	{
		FAudioManager::Get().SetLoopVolume(GetLoopName(), ComputeCurrentVolume());
		FAudioManager::Get().SetLoopPitch(GetLoopName(), Pitch);
	}
}

void AAudioVolume::EndPlay()
{
	StopVolumeAudio();
	Super::EndPlay();
}

void AAudioVolume::OnPossessedPawnEntered(APawn* /*Pawn*/)
{
	if (bAutoPlayWhileInside)
	{
		PlayVolumeAudio();
	}
}

void AAudioVolume::OnPossessedPawnExited(APawn* /*Pawn*/)
{
	if (GetOccupyingPawnCount() <= 0)
	{
		StopVolumeAudio();
	}
}

void AAudioVolume::PlayVolumeAudio()
{
	if (SoundPath.empty() || !EnsureLoaded())
	{
		return;
	}

	FAudioManager::Get().PlayLoop(GetAudioKey(), GetLoopName(), ComputeCurrentVolume(), Pitch);
	bPlaying = true;
}

void AAudioVolume::StopVolumeAudio()
{
	if (bPlaying)
	{
		FAudioManager::Get().StopLoop(GetLoopName());
	}
	bPlaying = false;
}

bool AAudioVolume::EnsureLoaded()
{
	if (bLoaded)
	{
		return true;
	}

	if (SoundPath.empty())
	{
		return false;
	}

	bLoaded = FAudioManager::Get().LoadAudio(GetAudioKey(), SoundPath, true);
	if (!bLoaded)
	{
		UE_LOG("[AudioVolume] Failed to load audio. Actor=%s Path=%s",
			GetName().c_str(),
			SoundPath.c_str());
	}
	return bLoaded;
}

float AAudioVolume::ComputeCurrentVolume() const
{
	const float BaseVolume = Clamp01(Volume);
	if (FadeDistance <= 0.0f || GetOccupyingPawnCount() > 0)
	{
		return BaseVolume;
	}
	return 0.0f;
}

FString AAudioVolume::GetAudioKey() const
{
	FString Key = "AudioVolume:";
	Key += SoundPath;
	return Key;
}

FString AAudioVolume::GetLoopName() const
{
	FString Name = "AudioVolumeLoop:";
	Name += GetName();
	Name += ":";
	Name += std::to_string(reinterpret_cast<std::uintptr_t>(this));
	return Name;
}
