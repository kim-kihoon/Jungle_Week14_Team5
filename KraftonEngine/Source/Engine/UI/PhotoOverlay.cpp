#include "UI/PhotoOverlay.h"

#include "Component/Primitive/PhotoPolaroidComponent.h"
#include "Component/Primitive/StaticMeshComponent.h"
#include "GameFramework/AActor.h"
#include "GameFramework/World.h"
#include "Math/Matrix.h"
#include "Math/Quat.h"
#include "Object/Object.h"
#include "Object/Ptr/WeakObjectPtr.h"
#include "Platform/Paths.h"
#include "Render/Types/MinimalViewInfo.h"
#include "WICTextureLoader.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <filesystem>

namespace
{
	constexpr float PhotoEjectSeconds = 0.65f;
	constexpr float PhotoVisibleSeconds = 4.8f;
	constexpr float DefaultFrameAspectRatio = 1672.0f / 941.0f;
	constexpr const char* HeldCameraMeshPath = "Content/Data/camera/camera_StaticMesh.uasset";
	constexpr const char* HeldCameraMeshFileName = "camera_StaticMesh.uasset";
	constexpr float HeldCameraPhotoForwardOffset = 0.06f;
	constexpr float HeldCameraPhotoRightOffset = 0.0f;
	constexpr float HeldCameraPhotoBaseUpOffset = 0.0f;
	constexpr float HeldCameraPhotoEjectUpDistance = 0.19f;

	bool bCaptureRequested = false;
	float VisibleSecondsRemaining = 0.0f;
	float DisplayTime = 0.0f;
	float DevelopTime = 0.0f;
	uint32 CapturedWidth = 0;
	uint32 CapturedHeight = 0;
	ID3D11Texture2D* CapturedTexture = nullptr;
	ID3D11ShaderResourceView* CapturedSRV = nullptr;
	uint32 FrameWidth = 0;
	uint32 FrameHeight = 0;
	ID3D11ShaderResourceView* FrameSRV = nullptr;
	TArray<TWeakObjectPtr<AActor>> CaptureHiddenActors;
	TWeakObjectPtr<UWorld> PendingCaptureWorld;
	TWeakObjectPtr<AActor> PhotoActor;
	TWeakObjectPtr<UPhotoPolaroidComponent> PhotoComponent;
	TWeakObjectPtr<UStaticMeshComponent> HeldCameraMeshComponent;

	std::filesystem::path ToProjectPath(const FString& Path)
	{
		std::filesystem::path Result(FPaths::ToWide(Path));
		if (Result.is_relative())
		{
			Result = std::filesystem::path(FPaths::RootDir()) / Result;
		}
		return Result;
	}

	float Clamp01(float Value)
	{
		return (std::max)(0.0f, (std::min)(1.0f, Value));
	}

	float EaseOutCubic(float Alpha)
	{
		const float InvAlpha = 1.0f - Clamp01(Alpha);
		return 1.0f - InvAlpha * InvAlpha * InvAlpha;
	}

	bool IsHeldCameraMesh(UStaticMeshComponent* Component)
	{
		if (!Component)
		{
			return false;
		}

		const FString& StaticMeshPath = Component->GetStaticMeshPath();
		return
			StaticMeshPath == HeldCameraMeshPath ||
			StaticMeshPath.find(HeldCameraMeshPath) != FString::npos ||
			StaticMeshPath.find(HeldCameraMeshFileName) != FString::npos;
	}

	UStaticMeshComponent* FindHeldCameraMeshComponent(UWorld* World)
	{
		if (!World)
		{
			return nullptr;
		}

		for (AActor* Actor : World->GetActors())
		{
			if (!Actor || Actor == PhotoActor.Get())
			{
				continue;
			}

			for (UActorComponent* ActorComponent : Actor->GetComponents())
			{
				UStaticMeshComponent* StaticMeshComponent = Cast<UStaticMeshComponent>(ActorComponent);
				if (IsHeldCameraMesh(StaticMeshComponent))
				{
					return StaticMeshComponent;
				}
			}
		}

		return nullptr;
	}

	UStaticMeshComponent* GetHeldCameraMeshComponent(UWorld* World)
	{
		UStaticMeshComponent* Component = HeldCameraMeshComponent.Get();
		if (Component && Component->GetOwner() && Component->GetOwner()->GetWorld() == World && IsHeldCameraMesh(Component))
		{
			return Component;
		}

		Component = FindHeldCameraMeshComponent(World);
		HeldCameraMeshComponent = Component;
		return Component;
	}

	void DestroyPhotoActor()
	{
		if (AActor* Actor = PhotoActor.Get())
		{
			if (UWorld* World = Actor->GetWorld())
			{
				World->DestroyActor(Actor);
			}
		}
		PhotoComponent.Reset();
		PhotoActor.Reset();
	}

	void SpawnPhotoActor(UWorld* World)
	{
		DestroyPhotoActor();
		if (!World || !CapturedSRV || !FrameSRV)
		{
			return;
		}

		AActor* Actor = World->SpawnActor<AActor>();
		if (!Actor)
		{
			return;
		}
		Actor->SetFName(FName("RuntimePolaroidPhoto"));
		Actor->AddTag(FName("Fake"));
		Actor->bNeedsTick = false;

		UPhotoPolaroidComponent* Component = Actor->AddComponent<UPhotoPolaroidComponent>();
		if (!Component)
		{
			World->DestroyActor(Actor);
			return;
		}

		Component->SetCastShadow(false);
		Component->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		Component->SetTextures(CapturedSRV, FrameSRV);
		Component->SetDisplayTime(0.0f);
		Component->SetDevelopTime(0.0f);
		Actor->SetRootComponent(Component);

		PhotoActor = Actor;
		PhotoComponent = Component;
	}

	void UpdatePhotoActorTransform()
	{
		UPhotoPolaroidComponent* Component = PhotoComponent.Get();
		AActor* Actor = PhotoActor.Get();
		UWorld* World = Actor ? Actor->GetWorld() : PendingCaptureWorld.Get();
		if (!Component || !Actor || !World)
		{
			return;
		}

		FMinimalViewInfo POV;
		if (!World->GetActivePOV(POV))
		{
			return;
		}

		const float EjectAlpha = Clamp01(DisplayTime / PhotoEjectSeconds);
		const float EjectEase = EaseOutCubic(EjectAlpha);
		FVector Forward = POV.Rotation.GetForwardVector();
		FVector Right = POV.Rotation.GetRightVector();
		FVector Up = POV.Rotation.GetUpVector();
		FVector Location =
			POV.Location +
			Forward * 0.225f +
			Up * (-0.22f + 0.22f * EjectEase);

		if (UStaticMeshComponent* HeldCameraMesh = GetHeldCameraMeshComponent(World))
		{
			Forward = HeldCameraMesh->GetForwardVector();
			Right = HeldCameraMesh->GetRightVector();
			Up = HeldCameraMesh->GetUpVector();
			Location =
				HeldCameraMesh->GetWorldLocation() +
				Forward * HeldCameraPhotoForwardOffset +
				Right * HeldCameraPhotoRightOffset +
				Up * (HeldCameraPhotoBaseUpOffset + HeldCameraPhotoEjectUpDistance * EjectEase);
		}

		FMatrix PhotoRotationMatrix;
		PhotoRotationMatrix.SetAxes(Forward, Right, Up);
		Component->SetWorldRotation(FQuat::FromMatrix(PhotoRotationMatrix));

		Component->SetWorldLocation(Location);
		Component->SetRelativeScale(FVector(0.1f, 0.1f, 0.1f));
		Component->SetDisplayTime(DisplayTime);
		Component->SetDevelopTime(DevelopTime);
	}
}

void FPhotoOverlay::RequestCapture()
{
	RestoreHiddenActors();
	bCaptureRequested = true;
}

void FPhotoOverlay::RequestCapture(UWorld* World, const FName& ExcludeActorTag)
{
	RestoreHiddenActors();
	PendingCaptureWorld = World;

	if (World && ExcludeActorTag.IsValid() && ExcludeActorTag != FName::None)
	{
		for (AActor* Actor : World->GetActors())
		{
			if (!Actor || !Actor->IsVisible() || !Actor->HasTag(ExcludeActorTag))
			{
				continue;
			}

			Actor->SetVisible(false);
			CaptureHiddenActors.push_back(TWeakObjectPtr<AActor>(Actor));
		}
	}

	bCaptureRequested = true;
}

void FPhotoOverlay::CapturePendingFromViewport(ID3D11Texture2D* SourceTexture)
{
	if (!bCaptureRequested)
	{
		return;
	}
	if (!SourceTexture)
	{
		bCaptureRequested = false;
		RestoreHiddenActors();
		return;
	}

	bCaptureRequested = false;
	if (!EnsureResources(SourceTexture))
	{
		RestoreHiddenActors();
		return;
	}

	ID3D11Device* Device = nullptr;
	SourceTexture->GetDevice(&Device);
	if (!Device)
	{
		RestoreHiddenActors();
		return;
	}

	ID3D11DeviceContext* Context = nullptr;
	Device->GetImmediateContext(&Context);
	EnsureFrameResource(Device);
	Device->Release();

	if (!Context)
	{
		RestoreHiddenActors();
		return;
	}

	Context->CopyResource(CapturedTexture, SourceTexture);
	Context->Release();
	RestoreHiddenActors();
	VisibleSecondsRemaining = PhotoVisibleSeconds;
	DisplayTime = 0.0f;
	DevelopTime = 0.0f;
	SpawnPhotoActor(PendingCaptureWorld.Get());
	UpdatePhotoActorTransform();
}

void FPhotoOverlay::Tick(float DeltaTime)
{
	if (VisibleSecondsRemaining > 0.0f)
	{
		VisibleSecondsRemaining -= DeltaTime;
		if (VisibleSecondsRemaining < 0.0f)
		{
			VisibleSecondsRemaining = 0.0f;
		}
		DisplayTime += DeltaTime;
		DevelopTime = DisplayTime > PhotoEjectSeconds ? DisplayTime - PhotoEjectSeconds : 0.0f;
		UpdatePhotoActorTransform();
	}
	else
	{
		DestroyPhotoActor();
	}
}

bool FPhotoOverlay::IsVisible()
{
	return VisibleSecondsRemaining > 0.0f && CapturedSRV;
}

ID3D11ShaderResourceView* FPhotoOverlay::GetSRV()
{
	return IsVisible() ? CapturedSRV : nullptr;
}

ID3D11ShaderResourceView* FPhotoOverlay::GetFrameSRV()
{
	return FrameSRV;
}

float FPhotoOverlay::GetDisplayTime()
{
	return DisplayTime;
}

float FPhotoOverlay::GetDevelopTime()
{
	return DevelopTime;
}

float FPhotoOverlay::GetEjectSeconds()
{
	return PhotoEjectSeconds;
}

float FPhotoOverlay::GetCaptureAspectRatio()
{
	return CapturedHeight > 0 ? static_cast<float>(CapturedWidth) / static_cast<float>(CapturedHeight) : 16.0f / 9.0f;
}

float FPhotoOverlay::GetFrameAspectRatio()
{
	return FrameHeight > 0 ? static_cast<float>(FrameWidth) / static_cast<float>(FrameHeight) : DefaultFrameAspectRatio;
}

void FPhotoOverlay::RestoreHiddenActors()
{
	for (TWeakObjectPtr<AActor>& ActorPtr : CaptureHiddenActors)
	{
		if (AActor* Actor = ActorPtr.Get())
		{
			Actor->SetVisible(true);
		}
	}
	CaptureHiddenActors.clear();
}

bool FPhotoOverlay::EnsureResources(ID3D11Texture2D* SourceTexture)
{
	D3D11_TEXTURE2D_DESC SourceDesc = {};
	SourceTexture->GetDesc(&SourceDesc);
	if (SourceDesc.Width == 0 || SourceDesc.Height == 0)
	{
		return false;
	}

	if (CapturedTexture && CapturedSRV && CapturedWidth == SourceDesc.Width && CapturedHeight == SourceDesc.Height)
	{
		return true;
	}

	ReleaseResources();

	ID3D11Device* Device = nullptr;
	SourceTexture->GetDevice(&Device);
	if (!Device)
	{
		return false;
	}

	D3D11_TEXTURE2D_DESC CaptureDesc = SourceDesc;
	CaptureDesc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
	CaptureDesc.CPUAccessFlags = 0;
	CaptureDesc.MiscFlags = 0;
	CaptureDesc.Usage = D3D11_USAGE_DEFAULT;

	HRESULT HR = Device->CreateTexture2D(&CaptureDesc, nullptr, &CapturedTexture);
	if (FAILED(HR) || !CapturedTexture)
	{
		Device->Release();
		return false;
	}
	CapturedTexture->SetPrivateData(WKPDID_D3DDebugObjectName, static_cast<UINT>(strlen("PhotoOverlayTexture")), "PhotoOverlayTexture");

	HR = Device->CreateShaderResourceView(CapturedTexture, nullptr, &CapturedSRV);
	Device->Release();
	if (FAILED(HR) || !CapturedSRV)
	{
		ReleaseResources();
		return false;
	}
	CapturedSRV->SetPrivateData(WKPDID_D3DDebugObjectName, static_cast<UINT>(strlen("PhotoOverlaySRV")), "PhotoOverlaySRV");

	CapturedWidth = SourceDesc.Width;
	CapturedHeight = SourceDesc.Height;
	return true;
}

bool FPhotoOverlay::EnsureFrameResource(ID3D11Device* Device)
{
	if (FrameSRV)
	{
		return true;
	}
	if (!Device)
	{
		return false;
	}

	const std::filesystem::path FramePath = ToProjectPath("Content/Texture/polaroid.png");
	ID3D11Resource* Resource = nullptr;
	ID3D11ShaderResourceView* SRV = nullptr;
	const HRESULT HR = DirectX::CreateWICTextureFromFileEx(
		Device,
		FramePath.c_str(),
		0,
		D3D11_USAGE_DEFAULT,
		D3D11_BIND_SHADER_RESOURCE,
		0,
		0,
		DirectX::WIC_LOADER_IGNORE_SRGB,
		&Resource,
		&SRV);

	if (FAILED(HR) || !SRV)
	{
		if (Resource)
		{
			Resource->Release();
		}
		return false;
	}

	if (Resource)
	{
		ID3D11Texture2D* Texture2D = nullptr;
		if (SUCCEEDED(Resource->QueryInterface(__uuidof(ID3D11Texture2D), reinterpret_cast<void**>(&Texture2D))) && Texture2D)
		{
			D3D11_TEXTURE2D_DESC Desc = {};
			Texture2D->GetDesc(&Desc);
			FrameWidth = Desc.Width;
			FrameHeight = Desc.Height;
			Texture2D->Release();
		}
		Resource->Release();
	}

	FrameSRV = SRV;
	FrameSRV->SetPrivateData(WKPDID_D3DDebugObjectName, static_cast<UINT>(strlen("PhotoOverlayFrameSRV")), "PhotoOverlayFrameSRV");
	return true;
}

void FPhotoOverlay::ReleaseResources()
{
	if (CapturedSRV)
	{
		CapturedSRV->Release();
		CapturedSRV = nullptr;
	}
	if (CapturedTexture)
	{
		CapturedTexture->Release();
		CapturedTexture = nullptr;
	}
	CapturedWidth = 0;
	CapturedHeight = 0;
}
