{
  Copyright 2014 Michalis Kamburelis.

  This file is part of "Little Things".

  "Little Things" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Little Things" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Implements the game logic, independent from Android / standalone. }
unit Game;

interface

uses CastleWindowTouch;

var
  Window: TCastleWindowTouch;

implementation

uses SysUtils, CastleVectors, CastleLog, CastleWindowProgress, CastleProgress,
  CastleWindow, CastleResources, CastleTerrain, CastleScene, X3DNodes,
  CastleCameras, CastleFilesUtils, Math, CastleKeysMouse, CastleWarnings,
  CastleSceneCore, CastleBoxes, CastleUtils, X3DLoad, X3DCameraUtils,
  CastleRenderer, Castle3D, CastlePrecalculatedAnimation, CastleLevels, CastlePlayer,
  CastleUIControls, CastleSoundEngine,
  GamePlay, GamePlayer, GameTitle;

{ One-time initialization. }
procedure ApplicationInitialize;
begin
  OnWarning := @OnWarningWrite;

  GeneratedCubeMapBias := Vector3Single(0, -1, 0);
  Progress.UserInterface := WindowProgressInterface;
  SceneManager := Window.SceneManager;

  SoundEngine.RepositoryURL := ApplicationData('sounds/index.xml');
  SoundEngine.MusicPlayer.MusicVolume := 0.5;

  Resources.LoadFromFiles;
  Levels.LoadFromFiles;
end;

function MyGetApplicationName: string;
begin
  Result := 'little_things';
end;

procedure WindowOpen(Container: TUIContainer);
begin
  StartPlayer;
  StartTitleScreen;
end;

procedure WindowPress(Container: TUIContainer; const Event: TInputPressRelease);
begin
  if TitleScreen then
    TitlePress(Event) else
    GamePress(Event);
end;

procedure WindowUpdate(Container: TUIContainer);
begin
  if not TitleScreen then
    GameUpdate(Window.Fps.UpdateSecondsPassed);
end;

procedure WindowRender(Container: TUIContainer);
begin
  if not TitleScreen then
    GameRender;
end;

initialization
  { This should be done as early as possible to mark our log lines correctly. }
  OnGetApplicationName := @MyGetApplicationName;

  { initialize Application callbacks }
  Application.OnInitialize := @ApplicationInitialize;

  { create Window and initialize Window callbacks }
  Window := TCastleWindowTouch.Create(Application);
  Window.OnOpen := @WindowOpen;
  Window.OnPress := @WindowPress;
  Window.OnUpdate := @WindowUpdate;
  Window.OnRender := @WindowRender;
  Window.RenderStyle := rs3D;
  Window.FpsShowOnCaption := true;
  Application.MainWindow := Window;
end.
