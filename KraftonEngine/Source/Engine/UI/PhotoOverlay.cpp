#include "UI/PhotoOverlay.h"

#include <cstring>

namespace
{
	constexpr int32 PhotoVisibleFrames = 180;

	bool bCaptureRequested = false;
	int32 VisibleFramesRemaining = 0;
	uint32 CapturedWidth = 0;
	uint32 CapturedHeight = 0;
	ID3D11Texture2D* CapturedTexture = nullptr;
	ID3D11ShaderResourceView* CapturedSRV = nullptr;
}

void FPhotoOverlay::RequestCapture()
{
	bCaptureRequested = true;
}

void FPhotoOverlay::CapturePendingFromViewport(ID3D11Texture2D* SourceTexture)
{
	if (!bCaptureRequested || !SourceTexture)
	{
		return;
	}

	bCaptureRequested = false;
	if (!EnsureResources(SourceTexture))
	{
		return;
	}

	ID3D11Device* Device = nullptr;
	SourceTexture->GetDevice(&Device);
	if (!Device)
	{
		return;
	}

	ID3D11DeviceContext* Context = nullptr;
	Device->GetImmediateContext(&Context);
	Device->Release();

	if (!Context)
	{
		return;
	}

	Context->CopyResource(CapturedTexture, SourceTexture);
	Context->Release();
	VisibleFramesRemaining = PhotoVisibleFrames;
}

void FPhotoOverlay::Tick()
{
	if (VisibleFramesRemaining > 0)
	{
		--VisibleFramesRemaining;
	}
}

bool FPhotoOverlay::IsVisible()
{
	return VisibleFramesRemaining > 0 && CapturedSRV;
}

ID3D11ShaderResourceView* FPhotoOverlay::GetSRV()
{
	return IsVisible() ? CapturedSRV : nullptr;
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
