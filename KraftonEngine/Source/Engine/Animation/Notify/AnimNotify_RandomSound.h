#pragma once

#include "Animation/Notify/AnimNotify.h"
#include "Core/Types/CoreTypes.h"

#include "Source/Engine/Animation/Notify/AnimNotify_RandomSound.generated.h"

UCLASS()
class UAnimNotify_RandomSound : public UAnimNotify
{
public:
	GENERATED_BODY()
	UAnimNotify_RandomSound() = default;
	~UAnimNotify_RandomSound() override = default;

	UPROPERTY(Edit, Save, Category="RandomSound", DisplayName="Sound Paths")
	TArray<FString> SoundPaths;

	UPROPERTY(Edit, Save, Category="RandomSound", DisplayName="Volume")
	float Volume = 1.0f;

	void Notify(USkeletalMeshComponent* MeshComp, UAnimSequenceBase* Anim) override;
};
