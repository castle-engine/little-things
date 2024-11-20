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

implementation

uses SysUtils, CastleVectors, CastleLog,
  CastleWindow, CastleResources, CastleTerrain, CastleScene, X3DNodes,
  CastleCameras, CastleFilesUtils, Math, CastleKeysMouse,
  CastleSceneCore, CastleBoxes, CastleUtils, X3DLoad, X3DCameraUtils,
  CastleTransform, CastleLevels, CastlePlayer,
  CastleUIControls, CastleSoundEngine, CastleGLUtils, CastleViewport,
  GamePlay, GamePlayer, GameTitle;

var
  Window: TCastleWindow;

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
  StartTitleScreen;
end;

type
  { View to contain whole UI and to handle events, like updates.
    TODO: We should split logic, into TViewTitle, TViewPlay in this game. }
  TMyView = class(TCastleView)
    function Press(const Event: TInputPressRelease): Boolean; override;
  end;

function TMyView.Press(const Event: TInputPressRelease): Boolean;
var
  Pos, Dir, Up, GravityUp: TVector3;
begin
  Result := inherited;
  if Result then Exit;

  if EnableDebugKeys(Container) then
  begin
    if Event.IsKey(key7) then
    begin
      SceneManager.Camera.GetView(Pos, Dir, Up);
      GravityUp := SceneManager.Camera.GravityUp;
      WritelnLog('Camera', MakeCameraStr(cvVrml2_X3d, false, Pos, Dir, Up, GravityUp));
      Exit(true);
    end;
  end;

  if TitleScreen then
    TitlePress(Container, Event)
  else
    GamePress(Container, Event);
end;

var
  MyView: TMyView;
initialization
  { initialize Application callbacks }
  Application.OnInitialize := @ApplicationInitialize;

  { create Window and initialize Window callbacks }
  Window := TCastleWindow.Create(Application);
  Window.FullScreen := true;
  Window.ParseParameters; // after setting FullScreen, to allow overriding it
  Window.FpsShowOnCaption := true;

  MyView := TMyView.Create(Application);
  Window.Container.View := MyView;

  Application.MainWindow := Window;
end.
