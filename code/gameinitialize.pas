{
  Copyright 2014-2024 Michalis Kamburelis.

  This file is part of "Little Things".

  "Little Things" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Little Things" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Implements the game logic, independent from Android / standalone. }
unit GameInitialize;

interface

uses CastleWindow;

var
  Window: TCastleWindow;

implementation

uses SysUtils, CastleVectors, CastleLog,
  CastleResources, CastleTerrain, CastleScene, X3DNodes,
  CastleCameras, CastleFilesUtils, Math, CastleKeysMouse,
  CastleSceneCore, CastleBoxes, CastleUtils, X3DLoad, X3DCameraUtils,
  CastleRenderer, CastleTransform, CastleLevels, CastlePlayer,
  CastleUIControls, CastleSoundEngine, CastleGLUtils, CastleViewport,
  GamePlay, GamePlayer, GameTitle;

{ One-time initialization. }
procedure ApplicationInitialize;
begin
  SceneManager := TGameSceneManager.Create(Application);
  SceneManager.FullSize := true;
  Window.Controls.InsertFront(SceneManager);

  SoundEngine.RepositoryURL := 'castle-data:/sounds/index.xml';
  SoundEngine.LoopingChannel[0].Volume := 0.5;

  //Resources.LoadFromFiles; // cannot search recursively in Android assets
  //Levels.LoadFromFiles; // cannot search recursively in Android assets
  Levels.AddFromFile('castle-data:/title/level.xml');
  Levels.AddFromFile('castle-data:/level/level.xml');

  StartPlayer;
  if UseDebugPart then
    StartGame else
    StartTitleScreen;
end;

procedure WindowPress(Container: TUIContainer; const Event: TInputPressRelease);
var
  Pos, Dir, Up, GravityUp: TVector3;
begin
  if EnableDebugKeys(Container) then
  begin
    if Event.IsKey(key7) then
    begin
      SceneManager.Camera.GetView(Pos, Dir, Up);
      GravityUp := SceneManager.Camera.GravityUp;
      WritelnLog('Camera', MakeCameraStr(cvVrml2_X3d, false, Pos, Dir, Up, GravityUp));
    end;
  end;

  if TitleScreen then
    TitlePress(Container, Event) else
    GamePress(Container, Event);
end;

initialization
  { initialize Application callbacks }
  Application.OnInitialize := @ApplicationInitialize;

  { create Window and initialize Window callbacks }
  Window := TCastleWindow.Create(Application);
  Window.FullScreen := true;
  Window.OnPress := @WindowPress;
  Window.FpsShowOnCaption := true;
  Application.MainWindow := Window;
end.
