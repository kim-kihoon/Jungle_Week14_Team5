#pragma once

#include "Core/Types/CoreTypes.h"
#include "Object/FName.h"

#include <d3d11.h>

class UWorld;

class FPhotoOverlay
{
public:
	static void RequestCapture();
	static void RequestCapture(UWorld* World, const FName& ExcludeActorTag);
	static void CapturePendingFromViewport(ID3D11Texture2D* SourceTexture);
	static void Tick(float DeltaTime);
	static bool IsVisible();
	static bool IsFlashVisible();
	static ID3D11ShaderResourceView* GetSRV();
	static ID3D11ShaderResourceView* GetFrameSRV();
	static float GetDisplayTime();
	static float GetFlashTime();
	static float GetDevelopTime();
	static float GetEjectSeconds();
	static float GetCaptureAspectRatio();
	static float GetFrameAspectRatio();

private:
	static void RestoreHiddenActors();
	static bool EnsureResources(ID3D11Texture2D* SourceTexture);
	static bool EnsureFrameResource(ID3D11Device* Device);
	static void ReleaseResources();
};
