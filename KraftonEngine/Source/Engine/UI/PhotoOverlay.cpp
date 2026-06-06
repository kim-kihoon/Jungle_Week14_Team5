#include "UI/PhotoOverlay.h"

#include "Platform/Paths.h"
#include "WICTextureLoader.h"

#include <cstring>
#include <filesystem>

namespace
{
	constexpr int32 PhotoVisibleFrames = 180;
	constexpr float DefaultFrameAspectRatio = 1672.0f / 941.0f;

	bool bCaptureRequested = false;
	int32 VisibleFramesRemaining = 0;
	uint32 CapturedWidth = 0;
	uint32 CapturedHeight = 0;
	ID3D11Texture2D* CapturedTexture = nullptr;
	ID3D11ShaderResourceView* CapturedSRV = nullptr;
	uint32 FrameWidth = 0;
	uint32 FrameHeight = 0;
	ID3D11ShaderResourceView* FrameSRV = nullptr;

	std::filesystem::path ToProjectPath(const FString& Path)
	{
		std::filesystem::path Result(FPaths::ToWide(Path));
		if (Result.is_relative())
		{
			Result = std::filesystem::path(FPaths::RootDir()) / Result;
		}
		return Result;
	}
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
	EnsureFrameResource(Device);
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

ID3D11ShaderResourceView* FPhotoOverlay::GetFrameSRV()
{
	return FrameSRV;
}

float FPhotoOverlay::GetCaptureAspectRatio()
{
	return CapturedHeight > 0 ? static_cast<float>(CapturedWidth) / static_cast<float>(CapturedHeight) : 16.0f / 9.0f;
}

float FPhotoOverlay::GetFrameAspectRatio()
{
	return FrameHeight > 0 ? static_cast<float>(FrameWidth) / static_cast<float>(FrameHeight) : DefaultFrameAspectRatio;
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
