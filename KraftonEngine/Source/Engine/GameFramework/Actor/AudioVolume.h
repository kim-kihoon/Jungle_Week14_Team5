#pragma once

#include "GameFramework/Actor/TriggerVolumeBase.h"

#include "Source/Engine/GameFramework/Actor/AudioVolume.generated.h"

UCLASS()
class AAudioVolume : public ATriggerVolumeBase
{
public:
	GENERATED_BODY()
	AAudioVolume() = default;
	~AAudioVolume() override = default;

	void BeginPlay() override;
	void Tick(float DeltaTime) override;
	void EndPlay() override;

	void OnPossessedPawnEntered(APawn* Pawn) override;
	void OnPossessedPawnExited(APawn* Pawn) override;

	UFUNCTION(Callable, Category="AudioVolume")
	void PlayVolumeAudio();
	UFUNCTION(Callable, Category="AudioVolume")
	void StopVolumeAudio();
	UFUNCTION(Pure, Category="AudioVolume")
	bool IsVolumeAudioPlaying() const { return bPlaying; }

private:
	bool EnsureLoaded();
	float ComputeCurrentVolume() const;
	FString GetAudioKey() const;
	FString GetLoopName() const;

private:
	UPROPERTY(Edit, Save, Category="AudioVolume", DisplayName="Sound Path", AssetType="Audio")
	FString SoundPath;

	UPROPERTY(Edit, Save, Category="AudioVolume", DisplayName="Auto Play While Inside")
	bool bAutoPlayWhileInside = true;

	UPROPERTY(Edit, Save, Category="AudioVolume", DisplayName="Volume", Min=0.0f, Max=1.0f, Speed=0.01f)
	float Volume = 1.0f;

	UPROPERTY(Edit, Save, Category="AudioVolume", DisplayName="Pitch", Min=0.1f, Max=4.0f, Speed=0.01f)
	float Pitch = 1.0f;

	UPROPERTY(Edit, Save, Category="AudioVolume", DisplayName="Fade Distance", Min=0.0f, Max=1000.0f, Speed=0.1f)
	float FadeDistance = 1.0f;

	bool bLoaded = false;
	bool bPlaying = false;
};
