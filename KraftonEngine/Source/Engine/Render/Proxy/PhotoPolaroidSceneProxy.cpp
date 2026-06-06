#include "Render/Proxy/PhotoPolaroidSceneProxy.h"

#include "Component/Primitive/PhotoPolaroidComponent.h"
#include "GameFramework/AActor.h"
#include "Materials/Material.h"
#include "Object/Reflection/ObjectFactory.h"
#include "Render/Shader/ShaderManager.h"

#include <algorithm>

namespace
{
	constexpr float FrameAspect = 1672.0f / 941.0f;
	constexpr float PhotoForwardOffset = 0.002f;

	float Clamp01(float Value)
	{
		return (std::max)(0.0f, (std::min)(1.0f, Value));
	}

	FVector4 PhotoTint(float DevelopTime)
	{
		if (DevelopTime < 0.2f)
		{
			return FVector4(1.0f, 1.0f, 1.0f, 0.98f);
		}
		if (DevelopTime < 0.6f)
		{
			const float Alpha = Clamp01((DevelopTime - 0.2f) / 0.4f);
			const float Gray = 0.50f + Alpha * 0.22f;
			return FVector4(Gray, Gray, Gray, 0.45f + Alpha * 0.25f);
		}
		if (DevelopTime < 1.0f)
		{
			const float Alpha = Clamp01((DevelopTime - 0.6f) / 0.4f);
			const float Value = 0.72f + Alpha * 0.28f;
			return FVector4(Value, Value, Value, 0.70f + Alpha * 0.20f);
		}
		if (DevelopTime < 1.3f)
		{
			const float Alpha = Clamp01((DevelopTime - 1.0f) / 0.3f);
			return FVector4(0.75f + Alpha * 0.25f, 0.75f + Alpha * 0.25f, 0.75f + Alpha * 0.25f, 0.90f + Alpha * 0.10f);
		}
		return FVector4(1.0f, 1.0f, 1.0f, 1.0f);
	}

	void AddQuad(
		TArray<FVertexPNCT>& Vertices,
		TArray<uint32>& Indices,
		float X,
		float Left,
		float Top,
		float Right,
		float Bottom,
		const FVector4& Color)
	{
		const uint32 Base = static_cast<uint32>(Vertices.size());
		const FVector Normal(1.0f, 0.0f, 0.0f);
		Vertices.push_back({ FVector(X, Left, Top), Normal, Color, FVector2(0.0f, 0.0f) });
		Vertices.push_back({ FVector(X, Right, Top), Normal, Color, FVector2(1.0f, 0.0f) });
		Vertices.push_back({ FVector(X, Right, Bottom), Normal, Color, FVector2(1.0f, 1.0f) });
		Vertices.push_back({ FVector(X, Left, Bottom), Normal, Color, FVector2(0.0f, 1.0f) });
		Indices.insert(Indices.end(), { Base + 0, Base + 1, Base + 2, Base + 0, Base + 2, Base + 3 });
	}
}

FPhotoPolaroidSceneProxy::FPhotoPolaroidSceneProxy(UPhotoPolaroidComponent* InComponent)
	: FPrimitiveSceneProxy(InComponent)
{
	ProxyFlags |= EPrimitiveProxyFlags::NeverCull;
	ProxyFlags &= ~EPrimitiveProxyFlags::SupportsOutline;
	ProxyFlags &= ~EPrimitiveProxyFlags::ShowAABB;
}

FPhotoPolaroidSceneProxy::~FPhotoPolaroidSceneProxy()
{
	MeshBufferStorage.Release();
	if (FrameMaterial)
	{
		UObjectManager::Get().DestroyObject(FrameMaterial);
		FrameMaterial = nullptr;
	}
	if (PhotoMaterial)
	{
		UObjectManager::Get().DestroyObject(PhotoMaterial);
		PhotoMaterial = nullptr;
	}
}

void FPhotoPolaroidSceneProxy::AddReferencedObjects(FReferenceCollector& Collector)
{
	FPrimitiveSceneProxy::AddReferencedObjects(Collector);
	Collector.AddReferencedObject(FrameMaterial);
	Collector.AddReferencedObject(PhotoMaterial);
}

UPhotoPolaroidComponent* FPhotoPolaroidSceneProxy::GetPhotoComponent() const
{
	return static_cast<UPhotoPolaroidComponent*>(GetOwner());
}

void FPhotoPolaroidSceneProxy::UpdateTransform()
{
	FPrimitiveSceneProxy::UpdateTransform();
}

void FPhotoPolaroidSceneProxy::UpdateMaterial()
{
	UPhotoPolaroidComponent* Comp = GetPhotoComponent();
	if (!Comp)
	{
		bVisible = false;
		return;
	}

	if (!FrameMaterial)
	{
		FrameMaterial = UMaterial::CreateTransient(
			ERenderPass::Transparent,
			EBlendState::AlphaBlend,
			EDepthStencilState::DepthReadOnly,
			ERasterizerState::SolidNoCull,
			FShaderManager::Get().GetOrCreate(EShaderPath::Billboard));
	}
	if (!PhotoMaterial)
	{
		PhotoMaterial = UMaterial::CreateTransient(
			ERenderPass::Transparent,
			EBlendState::AlphaBlend,
			EDepthStencilState::DepthReadOnly,
			ERasterizerState::SolidNoCull,
			FShaderManager::Get().GetOrCreate(EShaderPath::Billboard));
	}

	FrameMaterial->SetCachedSRV(EMaterialTextureSlot::Diffuse, Comp->GetFrameSRV());
	PhotoMaterial->SetCachedSRV(EMaterialTextureSlot::Diffuse, Comp->GetPhotoSRV());

	SectionDraws.clear();
	if (FrameMaterial && PhotoMaterial)
	{
		FMeshSectionDraw FrameSection;
		FrameSection.Material = FrameMaterial;
		FrameSection.FirstIndex = 0;
		FrameSection.IndexCount = 6;
		FrameSection.PassOverride = ERenderPass::Transparent;
		SectionDraws.push_back(FrameSection);

		FMeshSectionDraw PhotoSection;
		PhotoSection.Material = PhotoMaterial;
		PhotoSection.FirstIndex = 6;
		PhotoSection.IndexCount = 6;
		PhotoSection.PassOverride = ERenderPass::Transparent;
		SectionDraws.push_back(PhotoSection);
	}
}

void FPhotoPolaroidSceneProxy::UpdateMesh()
{
	UPhotoPolaroidComponent* Comp = GetPhotoComponent();
	if (!Comp)
	{
		bVisible = false;
		return;
	}

	CachedDisplayTime = Comp->GetDisplayTime();
	CachedDevelopTime = Comp->GetDevelopTime();
	MeshBuffer = &MeshBufferStorage;
	UpdateMaterial();
	MeshBufferStorage.Release();
}

bool FPhotoPolaroidSceneProxy::PrepareDrawBuffer(ID3D11Device* Device, ID3D11DeviceContext* Context, FDrawCommandBuffer& OutBuffer) const
{
	(void)Context;
	RebuildMesh(Device);

	if (!MeshBufferStorage.IsValid())
	{
		return false;
	}

	OutBuffer = {};
	OutBuffer.VB = MeshBufferStorage.GetVertexBuffer().GetBuffer();
	OutBuffer.VBStride = MeshBufferStorage.GetVertexBuffer().GetStride();
	OutBuffer.IB = MeshBufferStorage.GetIndexBuffer().GetBuffer();
	return OutBuffer.VB && OutBuffer.IB;
}

void FPhotoPolaroidSceneProxy::RebuildMesh(ID3D11Device* Device) const
{
	if (!Device || MeshBufferStorage.IsValid())
	{
		return;
	}

	UPhotoPolaroidComponent* Comp = GetPhotoComponent();
	const float DevelopTime = Comp ? Comp->GetDevelopTime() : 0.0f;

	const float FrameHeight = 1.0f;
	const float FrameWidth = FrameHeight * FrameAspect;
	const float FullTop = FrameHeight * 0.5f;
	const float FullBottom = -FrameHeight * 0.5f;
	const float FullLeft = -FrameWidth * 0.5f;
	const float FullRight = FrameWidth * 0.5f;
	const float PhotoLeft = FullLeft + FrameWidth * (58.0f / 1672.0f);
	const float PhotoRight = FullLeft + FrameWidth * (1614.0f / 1672.0f);
	const float PhotoTop = FullTop - FrameHeight * (103.0f / 941.0f);
	const float PhotoBottom = FullTop - FrameHeight * (801.0f / 941.0f);

	TMeshData<FVertexPNCT> MeshData;
	AddQuad(MeshData.Vertices, MeshData.Indices, 0.0f, FullLeft, FullTop, FullRight, FullBottom, FVector4(1.0f, 1.0f, 1.0f, 1.0f));
	AddQuad(MeshData.Vertices, MeshData.Indices, PhotoForwardOffset, PhotoLeft, PhotoTop, PhotoRight, PhotoBottom, PhotoTint(DevelopTime));

	MeshBufferStorage.Create(Device, MeshData);
}
