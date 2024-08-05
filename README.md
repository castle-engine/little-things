# Little Things

## This is a very old application; do not use this to learn Castle Game Engine!

This application was developed using a very old _Castle Game Engine_ version. It still builds with the latest engine version (it is even tested by [GitHub Actions](https://castle-engine.io/github_actions) to make sure we maintain backward-compatibility) but it's absolutely *not* how I would go about implementing this game type now.

*Do not use this game as a learning example.* Instead, get [latest Castle Game Engine](https://castle-engine.io/) and browse `examples` inside the installed engine.

This project is maintained here only:
- for historical purposes
- and as part of automated test to make sure we maintain backward-compatibility when developing new engine versions.

## Introduction

A pretty 3D game-like experience where you swim towards a sound, using Castle Game Engine.

Using Castle Game Engine, see http://castle-engine.sourceforge.net/ .

## Compiling

- Download Castle Game Engine
  http://castle-engine.sourceforge.net/engine.php

- Install the build tool of Castle Game Engine, see
  https://castle-engine.io/build_tool .

  Basically, you compile a "castle-engine" program, and place it on $PATH.
  And you set the environment variable $CASTLE_ENGINE_PATH to the directory
  that contains (as a child) castle_game_engine/ directory.

- Compile by simple "make" in this directory.

## Keys

Steer the boat:

* With arrows.
* W / S also work to move forward / backward.
* Rotate by moving the mouse.

Other keys:

* F5 - Save screen.
* Escape - Exit.

Debug keys:

* Ctrl-1/2/3/4 - Adjust the silhouette effect parameters.
* Ctrl-5 - Switch to Examine camera.
* Ctrl-6 - Cheat move to next part.
* Ctrl-8 - Toggle rendering debug things in 3D view.
* Ctrl-9/0/P/O - Adjust the scale and height of the generated terrain (only for the part with yellowish terrain).

## License

GNU GPL >= 2.
