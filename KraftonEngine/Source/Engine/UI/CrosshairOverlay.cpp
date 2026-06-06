#include "UI/CrosshairOverlay.h"

namespace
{
	bool bCrosshairVisible = false;
}

void FCrosshairOverlay::SetVisible(bool bInVisible)
{
	bCrosshairVisible = bInVisible;
}

bool FCrosshairOverlay::IsVisible()
{
	return bCrosshairVisible;
}
