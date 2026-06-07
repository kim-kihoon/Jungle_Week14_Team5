#include "AnimNotify_PlaySound.h"

#include "Component/Audio/AudioComponent.h"
#include "Component/Primitive/SkeletalMeshComponent.h"
#include "GameFramework/AActor.h"

namespace
{
	UAudioComponent* ResolveNotifyAudioComponent(USkeletalMeshComponent* MeshComp)
	{
		if (!IsValid(MeshComp))
		{
			return nullptr;
		}

		AActor* Owner = MeshComp->GetOwner();
		if (!IsValid(Owner))
		{
			return nullptr;
		}

		if (UAudioComponent* ExistingAudioComponent = Owner->GetComponentByClass<UAudioComponent>())
		{
			return ExistingAudioComponent;
		}

		UAudioComponent* NewAudioComponent = Owner->AddComponent<UAudioComponent>();
		if (IsValid(NewAudioComponent))
		{
			NewAudioComponent->SetAutoActivate(false);
			NewAudioComponent->SetHiddenInComponentTree(true);
			NewAudioComponent->SetComponentTickEnabled(false);
			NewAudioComponent->AttachToComponent(MeshComp);
		}
		return NewAudioComponent;
	}

	bool PlayNotifySoundPath(UAudioComponent* AudioComponent, const FString& SoundPath, float Volume, float Pitch)
	{
		if (!IsValid(AudioComponent) || SoundPath.empty())
		{
			return false;
		}

		AudioComponent->PlayOneShot(SoundPath, Volume, Pitch);
		return true;
	}
}

void UAnimNotify_PlaySound::Notify(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* /*Anim*/)
{
	UAudioComponent* AudioComponent = ResolveNotifyAudioComponent(MeshComp);
	if (!AudioComponent)
	{
		return;
	}

	const float TrackVolumeScale = GetDispatchVolumeScale();
	if (!Sounds.empty())
	{
		for (const FAnimNotifySoundEntry& Sound : Sounds)
		{
			PlayNotifySoundPath(AudioComponent, Sound.SoundPath, Sound.Volume * TrackVolumeScale, Sound.Pitch);
		}
		return;
	}

	bool bPlayedAny = false;
	for (const FString& Path : SoundPaths)
	{
		bPlayedAny = PlayNotifySoundPath(AudioComponent, Path, Volume * TrackVolumeScale, 1.0f) || bPlayedAny;
	}

	if (!bPlayedAny)
	{
		PlayNotifySoundPath(AudioComponent, SoundPath, Volume * TrackVolumeScale, 1.0f);
	}
}
