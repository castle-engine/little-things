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

  Progress.UserInterface := WindowProgressInterface;
  SceneManager := Window.SceneManager;

  SoundEngine.RepositoryURL := ApplicationData('sounds/index.xml');
  SoundEngine.MusicPlayer.MusicVolume := 0.5;

  //Resources.LoadFromFiles; // cannot search recursively in Android assets
  //Levels.LoadFromFiles; // cannot search recursively in Android assets
  Levels.AddFromFile(ApplicationData('title/level.xml'));
  Levels.AddFromFile(ApplicationData('level/level.xml'));

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
  Pos, Dir, Up, GravityUp: TVector3Single;
begin
  if EnableDebugKeys(Container) then
  begin
    if Event.IsKey(K_7) then
    begin
      InitializeLog;
      Player.Camera.GetView(Pos, Dir, Up, GravityUp);
      WritelnLog('Camera', MakeCameraStr(cvVrml2_X3d, false, Pos, Dir, Up, GravityUp));
    end;
  end;

  if TitleScreen then
    TitlePress(Container, Event) else
    GamePress(Container, Event);
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
  Window.OnPress := @WindowPress;
  Window.OnUpdate := @WindowUpdate;
  Window.OnRender := @WindowRender;
  Window.RenderStyle := rs3D;
  Window.FpsShowOnCaption := true;
  Application.MainWindow := Window;
end.
