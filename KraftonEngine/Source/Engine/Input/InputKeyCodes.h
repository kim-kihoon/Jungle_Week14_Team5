#pragma once

#include "Core/Types/CoreTypes.h"

// Human-readable key name helpers for editor/LuaBlueprint/Lua bindings.
// Runtime input still stores virtual-key integers internally, but user-facing
// authoring should use stable names such as "Space", "W", "LeftMouseButton".
int32 ResolveInputKeyCode(const FString& KeyName);
FString GetInputKeyName(int32 KeyCode);
const TArray<FString>& GetKnownInputKeyNames();
