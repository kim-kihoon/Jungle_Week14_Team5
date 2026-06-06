#include "Component/Audio/AudioComponent.h"

#include "Audio/AudioManager.h"
#include "Component/Camera/CameraComponent.h"
#include "Core/Logging/Log.h"
#include "GameFramework/AActor.h"
#include "GameFramework/Camera/PlayerCameraManager.h"
#include "GameFramework/GameMode/PlayerController.h"
#include "GameFramework/Pawn/Pawn.h"
#include "GameFramework/World.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>

namespace
{
	float Clamp01(float Value)
	{
		return std::max(0.0f, std::min(1.0f, Value));
	}

	FString MakeObjectScopedName(const UObject* Object)
	{
		if (!Object)
		{
			return "None";
		}

		FString Name = Object->GetName();
		Name += ":";
		Name += std::to_string(reinterpret_cast<std::uintptr_t>(Object));
		return Name;
	}
}

void UAudioComponent::BeginPlay()
{
	Super::BeginPlay();

	if (bAutoPlay)
	{
		Play();
	}
}

void UAudioComponent::EndPlay()
{
	Stop();
	Super::EndPlay();
}

void UAudioComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction& ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);

	if (!bPlaying || !bLoop)
	{
		return;
	}

	FAudioManager::Get().SetLoopPitch(GetLoopName(), Pitch);
	if (bSpatialize)
	{
		FAudioManager::Get().SetLoop3DAttributes(
			GetLoopName(),
			GetWorldLocation(),
			MinDistance,
			std::max(MaxDistance, MinDistance));
		FAudioManager::Get().SetLoopVolume(GetLoopName(), Clamp01(Volume));
	}
	else
	{
		FAudioManager::Get().SetLoopVolume(GetLoopName(), ComputeAttenuatedVolume());
	}
}

void UAudioComponent::Play()
{
	if (SoundPath.empty() || !EnsureLoaded())
	{
		return;
	}

	FAudio3DPlaySettings Settings3D;
	if (bSpatialize)
	{
		Settings3D.bEnabled = true;
		Settings3D.Position = GetWorldLocation();
		Settings3D.MinDistance = MinDistance;
		Settings3D.MaxDistance = std::max(MaxDistance, MinDistance);
	}

	const float PlayVolume = bSpatialize ? Clamp01(Volume) : ComputeAttenuatedVolume();
	const FAudio3DPlaySettings* Settings3DPtr = bSpatialize ? &Settings3D : nullptr;
	if (bLoop)
	{
		FAudioManager::Get().PlayLoop(GetAudioKey(), GetLoopName(), PlayVolume, Pitch, Settings3DPtr);
		bPlaying = true;
	}
	else
	{
		FAudioManager::Get().PlayAudio(GetAudioKey(), PlayVolume, Pitch, Settings3DPtr);
		bPlaying = false;
	}
}

void UAudioComponent::Stop()
{
	if (bLoop && bPlaying)
	{
		FAudioManager::Get().StopLoop(GetLoopName());
	}
	bPlaying = false;
}

void UAudioComponent::SetVolume(float InVolume)
{
	Volume = Clamp01(InVolume);
	if (bPlaying && bLoop)
	{
		const float LoopVolume = bSpatialize ? Volume : ComputeAttenuatedVolume();
		FAudioManager::Get().SetLoopVolume(GetLoopName(), LoopVolume);
	}
}

bool UAudioComponent::EnsureLoaded()
{
	if (bLoaded)
	{
		return true;
	}

	if (SoundPath.empty())
	{
		return false;
	}

	bLoaded = FAudioManager::Get().LoadAudio(GetAudioKey(), SoundPath, bLoop, bSpatialize);
	if (!bLoaded)
	{
		UE_LOG("[AudioComponent] Failed to load audio. Component=%s Path=%s",
			GetName().c_str(),
			SoundPath.c_str());
	}
	return bLoaded;
}

float UAudioComponent::ComputeAttenuatedVolume() const
{
	const float BaseVolume = Clamp01(Volume);
	if (!bSpatialize)
	{
		return BaseVolume;
	}

	const float EffectiveMaxDistance = std::max(MaxDistance, MinDistance);
	if (EffectiveMaxDistance <= 0.0f)
	{
		return BaseVolume;
	}

	const float Distance = FVector::Distance(GetWorldLocation(), ResolveListenerLocation());
	if (Distance <= MinDistance)
	{
		return BaseVolume;
	}
	if (Distance >= EffectiveMaxDistance)
	{
		return 0.0f;
	}

	const float T = (Distance - MinDistance) / std::max(EffectiveMaxDistance - MinDistance, 0.001f);
	const float Attenuation = std::pow(1.0f - Clamp01(T), std::max(FalloffExponent, 0.1f));
	return BaseVolume * Attenuation;
}

FVector UAudioComponent::ResolveListenerLocation() const
{
	if (UWorld* World = GetWorld())
	{
		if (APlayerController* PC = World->GetFirstPlayerController())
		{
			if (APlayerCameraManager* CameraManager = PC->GetPlayerCameraManager())
			{
				if (UCameraComponent* Camera = CameraManager->GetActiveCamera())
				{
					return Camera->GetWorldLocation();
				}
			}

			if (APawn* Pawn = PC->GetPossessedPawn())
			{
				return Pawn->GetActorLocation();
			}
		}
	}

	return GetWorldLocation();
}

FString UAudioComponent::GetAudioKey() const
{
	FString Key = "AudioComponent:";
	Key += SoundPath;
	return Key;
}

FString UAudioComponent::GetLoopName() const
{
	FString Name = "AudioComponentLoop:";
	if (AActor* Owner = GetOwner())
	{
		Name += Owner->GetName();
		Name += ":";
	}
	Name += MakeObjectScopedName(this);
	return Name;
}
