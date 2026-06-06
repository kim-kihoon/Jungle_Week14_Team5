#include "Game/Player/HospitalPlayerActor.h"

#include "Component/Light/SpotLightComponent.h"
#include "Component/Primitive/SkeletalMeshComponent.h"

namespace
{
	const FName MuzzleSocketName("Muzzle");
}

void AHospitalPlayerActor::InitDefaultComponents(const FString& SkeletalMeshFileName, const FString& ScriptFile)
{
	ALuaCharacter::InitDefaultComponents(SkeletalMeshFileName, ScriptFile);
	EnsurePistolMuzzleFlashLight();
}

void AHospitalPlayerActor::InitDefaultComponents(const FString& SkeletalMeshFileName)
{
	InitDefaultComponents(SkeletalMeshFileName, FString());
}

void AHospitalPlayerActor::PostDuplicate()
{
	ALuaCharacter::PostDuplicate();
	PistolMuzzleFlashLight = GetComponentByClass<USpotLightComponent>();
}

void AHospitalPlayerActor::BeginPlay()
{
	ALuaCharacter::BeginPlay();
	EnsurePistolMuzzleFlashLight();
	SetPistolMuzzleFlashVisible(false);
}

void AHospitalPlayerActor::Tick(float DeltaTime)
{
	ALuaCharacter::Tick(DeltaTime);

	if (PistolMuzzleFlashRemaining <= 0.0f)
	{
		return;
	}

	PistolMuzzleFlashRemaining -= DeltaTime;
	if (PistolMuzzleFlashRemaining <= 0.0f)
	{
		PistolMuzzleFlashRemaining = 0.0f;
		SetPistolMuzzleFlashVisible(false);
	}
}

void AHospitalPlayerActor::PlayPistolFireEffect()
{
	EnsurePistolMuzzleFlashLight();
	PistolMuzzleFlashRemaining = PistolMuzzleFlashDuration;
	SetPistolMuzzleFlashVisible(true);
}

void AHospitalPlayerActor::EnsurePistolMuzzleFlashLight()
{
	if (PistolMuzzleFlashLight.IsValid())
	{
		return;
	}

	USpotLightComponent* NewLight = AddComponent<USpotLightComponent>();
	if (!NewLight)
	{
		return;
	}

	PistolMuzzleFlashLight = NewLight;

	if (USkeletalMeshComponent* MeshComponent = GetMesh())
	{
		NewLight->AttachToComponent(MeshComponent, MuzzleSocketName);
	}

	NewLight->SetRelativeLocation(FVector::ZeroVector);
	NewLight->SetRelativeRotation(FRotator::ZeroRotator);
	NewLight->SetIntensity(8.0f);
	NewLight->SetLightColor(FVector4(1.0f, 0.78f, 0.45f, 1.0f));
	NewLight->SetAttenuationRadius(2.0f);
	NewLight->SetInnerConeAngle(12.0f);
	NewLight->SetOuterConeAngle(35.0f);
	NewLight->SetCastShadows(false);
	NewLight->SetVisible(false);
}

void AHospitalPlayerActor::SetPistolMuzzleFlashVisible(bool bVisible)
{
	if (USpotLightComponent* Light = PistolMuzzleFlashLight.Get())
	{
		Light->SetVisible(bVisible);
	}
}
