{
  Copyright 2014-2017 Michalis Kamburelis.

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
  CastleCameras, CastleFilesUtils, Math, CastleKeysMouse,
  CastleSceneCore, CastleBoxes, CastleUtils, X3DLoad, X3DCameraUtils,
  CastleRenderer, CastleTransform, CastleLevels, CastlePlayer,
  CastleUIControls, CastleSoundEngine, CastleGLUtils,
  GamePlay, GamePlayer, GameTitle;

{ One-time initialization. }
procedure ApplicationInitialize;
begin
  Progress.UserInterface := WindowProgressInterface;
  SceneManager := Window.SceneManager;

  SoundEngine.RepositoryURL := ApplicationData('sounds/index.xml');
  SoundEngine.MusicPlayer.Volume := 0.5;

  //Resources.LoadFromFiles; // cannot search recursively in Android assets
  //Levels.LoadFromFiles; // cannot search recursively in Android assets
  Levels.AddFromFile(ApplicationData('title/level.xml'));
  Levels.AddFromFile(ApplicationData('level/level.xml'));

  { EnableFixedFunction is needed for debug view (Ctrl + 8) to work,
    also water works better and faster in this case on trees (initial) level. }
  GLFeatures.EnableFixedFunction := true;

  StartPlayer;
  if UseDebugPart then
    StartGame else
    StartTitleScreen;
end;

function MyGetApplicationName: string;
begin
  Result := 'little_things';
end;

procedure WindowPress(Container: TUIContainer; const Event: TInputPressRelease);
var
  Pos, Dir, Up, GravityUp: TVector3;
begin
  if EnableDebugKeys(Container) then
  begin
    if Event.IsKey(K_7) then
    begin
      Player.Camera.GetView(Pos, Dir, Up, GravityUp);
      WritelnLog('Camera', MakeCameraStr(cvVrml2_X3d, false, Pos, Dir, Up, GravityUp));
    end;
  end;

  if TitleScreen then
    TitlePress(Container, Event) else
    GamePress(Container, Event);
end;

initialization
  { This should be done as early as possible to mark our log lines correctly. }
  OnGetApplicationName := @MyGetApplicationName;

  InitializeLog;

  { initialize Application callbacks }
  Application.OnInitialize := @ApplicationInitialize;

  { create Window and initialize Window callbacks }
  Window := TCastleWindowTouch.Create(Application);
  Window.OnPress := @WindowPress;
  Window.FpsShowOnCaption := true;
  Application.MainWindow := Window;
end.
