#include "AnimNotify_RandomSound.h"

#include "Audio/AudioManager.h"
#include "Core/Logging/Log.h"

#include <random>

namespace
{
	static TSet<FString> GLoadedRandomSoundPaths;

	FString PickRandomSoundPath(const TArray<FString>& SoundPaths)
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
			return FString();
		}

		static std::mt19937 RNG{ std::random_device{}() };
		std::uniform_int_distribution<size_t> Dist(0, Candidates.size() - 1);
		return *Candidates[Dist(RNG)];
	}
}

void UAnimNotify_RandomSound::Notify(USkeletalMeshComponent* /*MeshComp*/, UAnimSequenceBase* /*Anim*/)
{
	const FString SoundPath = PickRandomSoundPath(SoundPaths);
	if (SoundPath.empty())
	{
		return;
	}

	const FString Key = FString("AnimNotifyRandom:") + SoundPath;
	if (GLoadedRandomSoundPaths.find(SoundPath) == GLoadedRandomSoundPaths.end())
	{
		if (FAudioManager::Get().LoadAudio(Key, SoundPath, /*bLoop=*/false))
		{
			GLoadedRandomSoundPaths.insert(SoundPath);
		}
		else
		{
			UE_LOG("[AnimNotify_RandomSound] LoadAudio failed: %s", SoundPath.c_str());
			return;
		}
	}

	FAudioManager::Get().PlayAudio(Key, Volume);
}
