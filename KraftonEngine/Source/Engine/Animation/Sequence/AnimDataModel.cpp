#include "AnimDataModel.h"
#include "Animation/Notify/AnimNotify.h"
#include "Animation/Notify/AnimNotifyState.h"
#include "Object/GarbageCollection.h"
#include "Object/Object.h"

void UAnimDataModel::Serialize(FArchive& Ar)
{
    UObject::Serialize(Ar);

    Ar << PlayLength;
    Ar << FrameRate;
    Ar << NumFrames;
    Ar << BoneAnimationTracks;

    // Morph curves are authored data owned by this animation. They are appended before notifies.
    Ar << MorphTargetCurves;

    // Notifies 는 Outer 인지 직렬화 — Notify/NotifyState 객체 클래스명 + UPROPERTY(Save) payload
    // 까지 round-trip. ObjectFactory::Create 가 Outer 를 받아야 라이프타임 체인 형성되므로
    // TArray operator<< (raw 만) 사용 못 함, 명시적 루프로 entry 별 Serialize(Ar, this) 호출.
    int32 NotifyCount = static_cast<int32>(Notifies.size());
    Ar << NotifyCount;
    if (Ar.IsLoading())
    {
        Notifies.clear();
        Notifies.resize(NotifyCount);
    }
    for (int32 i = 0; i < NotifyCount; ++i)
    {
        Notifies[i].Serialize(Ar, this);
    }
}


void UAnimDataModel::AddReferencedObjects(FReferenceCollector& Collector)
{
    UObject::AddReferencedObjects(Collector);
    for (FAnimNotifyEvent& NotifyEvent : Notifies)
    {
        if (NotifyEvent.Notify && !IsValid(NotifyEvent.Notify))
        {
            NotifyEvent.Notify = nullptr;
        }
        if (NotifyEvent.NotifyState && !IsValid(NotifyEvent.NotifyState))
        {
            NotifyEvent.NotifyState = nullptr;
        }
        Collector.AddReferencedObject(NotifyEvent.Notify, "AnimDataModel.Notify");
        Collector.AddReferencedObject(NotifyEvent.NotifyState, "AnimDataModel.NotifyState");
    }
}
