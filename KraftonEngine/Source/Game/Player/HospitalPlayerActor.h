#pragma once

#include "GameFramework/Pawn/LuaCharacter.h"
#include "Object/Ptr/WeakObjectPtr.h"

class USpotLightComponent;

#include "Source/Game/Player/HospitalPlayerActor.generated.h"

UCLASS()
class AHospitalPlayerActor : public ALuaCharacter
{
public:
	GENERATED_BODY()
	AHospitalPlayerActor() = default;
	~AHospitalPlayerActor() override = default;

	void InitDefaultComponents(const FString& SkeletalMeshFileName, const FString& ScriptFile);
	void InitDefaultComponents(const FString& SkeletalMeshFileName) override;
	void PostDuplicate() override;
	void BeginPlay() override;
	void Tick(float DeltaTime) override;

	void PlayPistolFireEffect();

protected:
	void EnsurePistolMuzzleFlashLight();
	void SetPistolMuzzleFlashVisible(bool bVisible);

private:
	TWeakObjectPtr<USpotLightComponent> PistolMuzzleFlashLight = nullptr;
	float PistolMuzzleFlashDuration = 0.06f;
	float PistolMuzzleFlashRemaining = 0.0f;
};
