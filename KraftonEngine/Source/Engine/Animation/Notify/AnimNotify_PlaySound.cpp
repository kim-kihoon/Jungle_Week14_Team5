#include "AnimNotify_PlaySound.h"

#include "Audio/AudioManager.h"
#include "Core/Logging/Log.h"

namespace
{
	static TSet<FString> GLoadedPlaySoundPaths;

	bool PlayNotifySoundPath(const FString& SoundPath, float Volume, float Pitch)
	{
		if (SoundPath.empty())
		{
			return false;
		}

		const FString Key = FString("AnimNotify:") + SoundPath;
		if (GLoadedPlaySoundPaths.find(SoundPath) == GLoadedPlaySoundPaths.end())
		{
			if (FAudioManager::Get().LoadAudio(Key, SoundPath, /*bLoop=*/false))
			{
				GLoadedPlaySoundPaths.insert(SoundPath);
			}
			else
			{
				UE_LOG("[AnimNotify_PlaySound] LoadAudio failed: %s", SoundPath.c_str());
				return false;
			}
		}

		FAudioManager::Get().PlayAudio(Key, Volume, Pitch);
		return true;
	}
}

void UAnimNotify_PlaySound::Notify(USkeletalMeshComponent* /*MeshComp*/, UAnimSequenceBase* /*Anim*/)
{
	const float TrackVolumeScale = GetDispatchVolumeScale();
	if (!Sounds.empty())
	{
		for (const FAnimNotifySoundEntry& Sound : Sounds)
		{
			PlayNotifySoundPath(Sound.SoundPath, Sound.Volume * TrackVolumeScale, Sound.Pitch);
		}
		return;
	}

	bool bPlayedAny = false;
	for (const FString& Path : SoundPaths)
	{
		bPlayedAny = PlayNotifySoundPath(Path, Volume * TrackVolumeScale, 1.0f) || bPlayedAny;
	}

	if (!bPlayedAny)
	{
		PlayNotifySoundPath(SoundPath, Volume * TrackVolumeScale, 1.0f);
	}
}
