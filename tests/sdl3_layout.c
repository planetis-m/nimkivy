/* The C side of tsdl3's layout check: sizeof of the structs that
   nimkivy/sdl3/sdl.nim declares, as the C compiler sees them in the header. */
#include <SDL3/SDL.h>
#include <string.h>

#define SIZE(T) if (strcmp(name, #T) == 0) return (long long)sizeof(T);

long long sdl3CSizeof(const char *name) {
  SIZE(SDL_Rect) SIZE(SDL_FRect) SIZE(SDL_FPoint) SIZE(SDL_Color)
  SIZE(SDL_FColor) SIZE(SDL_Vertex) SIZE(SDL_Surface) SIZE(SDL_AudioSpec)
  SIZE(SDL_CommonEvent) SIZE(SDL_QuitEvent) SIZE(SDL_WindowEvent)
  SIZE(SDL_KeyboardEvent) SIZE(SDL_MouseMotionEvent)
  SIZE(SDL_MouseButtonEvent) SIZE(SDL_MouseWheelEvent)
  SIZE(SDL_TouchFingerEvent) SIZE(SDL_Event)
  return -1;
}
