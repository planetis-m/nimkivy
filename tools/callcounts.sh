#!/bin/sh
# Total calls of the functions PROFILE.md counts, from a callgrind output
# file (tools/profile.sh): SDL drawing calls, nimkivy's property and event
# dispatch, layouts, text and image loading, and allocations. Function
# names in the file are compressed ("cfn=(12) name" once, then "cfn=(12)");
# every "calls=N" line belongs to the cfn before it.
#
#   sh tools/callcounts.sh tests/out/profile/callgrind.out
set -eu
awk '
/^c?fn=\(/ {
  id = $0; sub(/^c?fn=/, "", id); sub(/\).*/, ")", id)
  name = $0; sub(/^c?fn=\([0-9]+\) ?/, "", name)
  if (name != "") names[id] = name
  if ($0 ~ /^cfn=/) cur = id
  next
}
/^calls=/ { n = $0; sub(/^calls=/, "", n); sub(/ .*/, "", n); calls[cur] += n }
END {
  for (id in calls) {
    nm = names[id]
    if (nm ~ /^(SDL_RenderGeometry|SDL_RenderLines|SDL_RenderTexture|SDL_RenderPresent|SDL_RenderClear|SDL_SetRenderTarget|SDL_SetRenderClipRect|SDL_CreateTexture|SDL_CreateTextureFromSurface|SDL_UpdateTexture|SDL_PollEvent|IMG_Load|TTF_OpenFont|TTF_GetStringSize|TTF_Render[A-Za-z_]*|malloc|free|calloc|realloc|rawAlloc_.*|rawDealloc_.*)$/ ||
        nm ~ /^(dispatch|set|get|doLayout|draw|drawTriangles|drawLineStrip|apply|render|renderLines|renderText|getExtents|layoutText|textureUpdate|loadTexture|newTexture|handle|blit|onDraw|idle|tick|tickDraw)_[0-9]+_[a-z0-9]+$/)
      printf "%12d  %s\n", calls[id], nm
  }
}' "$1" | sort -k2
