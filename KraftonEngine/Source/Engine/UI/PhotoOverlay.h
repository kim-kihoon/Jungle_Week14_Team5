#pragma once

#include "Core/Types/CoreTypes.h"

#include <d3d11.h>

class FPhotoOverlay
{
public:
	static void RequestCapture();
	static void CapturePendingFromViewport(ID3D11Texture2D* SourceTexture);
	static void Tick();
	static bool IsVisible();
	static ID3D11ShaderResourceView* GetSRV();
	static ID3D11ShaderResourceView* GetFrameSRV();
	static float GetCaptureAspectRatio();
	static float GetFrameAspectRatio();

private:
	static bool EnsureResources(ID3D11Texture2D* SourceTexture);
	static bool EnsureFrameResource(ID3D11Device* Device);
	static void ReleaseResources();
};
