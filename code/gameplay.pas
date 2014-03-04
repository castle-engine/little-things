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

{ Game routines. }
unit GamePlay;

{$I castleconf.inc}

interface

uses CastleScene, Castle3D, X3DNodes, CastlePlayer, CastleLevels, CastleKeysMouse;

type
  TPart = (pForest, pCave, pLake, pIsland);
const
  PartNames: array [TPart] of string = ('forest', 'cave', 'lake', 'island');

var
  SceneManager: TGameSceneManager;

procedure LoadPart(const Part: TPart);

procedure StartGame;
procedure GameUpdate(const SecondsPassed: Single);
procedure GamePress(const Event: TInputPressRelease);
procedure GameRender;

implementation

uses SysUtils, CastleVectors, CastleLog, CastleWindowProgress, CastleProgress,
  CastleWindow, CastleResources, CastleTerrain, CastleCameras, CastleFilesUtils,
  Math, CastleWarnings, CastleSceneCore, CastleBoxes, CastleTimeUtils,
  CastleGL, CastleGLUtils, CastleGLShaders, Game,
  CastleUtils, X3DLoad, X3DCameraUtils, CastleRenderer, CastlePrecalculatedAnimation,
  CastleSceneManager, CastleColors, CastleRenderingCamera, CastleNoise;

var
  Player: TPlayer; //< same thing as Window.SceneManager.Player
  DefaultMoveSpeed: Single;
  VisibilityLimit: Single;
  RenderDebug3D: boolean;

  CurrentPart: TPart;
  CurrentPartScene: TCastleScene;

  WaterTransform: TTransformNode;
  DogTransform: TTransformNode;
  PaintedEffect: TScreenEffectNode;
  AvatarTransform: T3DTransform;

  WindTime: TFloatTime;
  SeedDirection: Cardinal;
  SeedSpeed: Cardinal;

const
  HeightOverAvatar = 2.0; // do not make it ultra-large, to allow swimming under passages
  WaterHeight = 0.0;
  MarginOverWater = 0.5;

{ routines ------------------------------------------------------------------- }

function AvatarPositionFromCamera(const CameraPosition: TVector3Single): TVector3Single;
begin
  Result := CameraPosition +
    Player.Camera.DirectionInGravityPlane * Player.Camera.RotationHorizontalPivot;
  Result[SceneManager.Items.GravityCoordinate] := WaterHeight; // constant height on the water
end;

function OverWater(Point: TVector3Single; out Height: Single): boolean;
var
  Collision: TRayCollision;
begin
  Point[SceneManager.Items.GravityCoordinate] := HeightOverAvatar;
  SceneManager.MainScene.Disable; // do not hit water surface
  AvatarTransform.Disable; // do not hit avatar
  try
    Collision := SceneManager.Items.WorldRay(Point, -SceneManager.GravityUp);
    Result := (Collision = nil) or
              (Collision.First.Point[SceneManager.Items.GravityCoordinate] < WaterHeight);
    if not Result then
      Height := Collision.First.Point[SceneManager.Items.GravityCoordinate];
    FreeAndNil(Collision);
  finally
    SceneManager.MainScene.Enable;
    AvatarTransform.Enable;
  end;
end;

function OverWater(Point: TVector3Single): boolean;
var
  Height: Single;
begin
  Result := OverWater(Point, Height { ignore });
end;

function OverWaterAround(const Point: TVector3Single; const Margin: Single): boolean;
var
  Side: TVector3Single;
begin
  Side := VectorProduct(Player.Camera.DirectionInGravityPlane, SceneManager.GravityUp);
  Result :=
    { to protect forward movement }
    OverWater(Point + Player.Camera.DirectionInGravityPlane * Margin) and
    OverWater(Point + Player.Camera.DirectionInGravityPlane * Margin + Side * Margin) and
    OverWater(Point + Player.Camera.DirectionInGravityPlane * Margin - Side * Margin) and
    OverWater(Point + Player.Camera.DirectionInGravityPlane * Margin + Side * Margin / 2) and
    OverWater(Point + Player.Camera.DirectionInGravityPlane * Margin - Side * Margin / 2) and

    { to protect backward movement }
    OverWater(Point - Player.Camera.DirectionInGravityPlane * Margin * 2) and
    OverWater(Point - Player.Camera.DirectionInGravityPlane * Margin * 2 + Side * Margin) and
    OverWater(Point - Player.Camera.DirectionInGravityPlane * Margin * 2 - Side * Margin);
    // OverWater(Point + Vector3Single(-Margin, 0, -Margin)) and
    // OverWater(Point + Vector3Single(-Margin, 0,  Margin)) and
    // OverWater(Point + Vector3Single( Margin, 0, -Margin)) and
    // OverWater(Point + Vector3Single( Margin, 0,  Margin)) and

    // OverWater(Point + Vector3Single(-Margin, 0,       0)) and
    // OverWater(Point + Vector3Single( Margin, 0,       0)) and
    // OverWater(Point + Vector3Single(      0, 0, -Margin)) and
    // OverWater(Point + Vector3Single(      0, 0,  Margin));
end;

function OverWaterFactor(const Point: TVector3Single): Single;
begin
  if not OverWater(Point) then
    Result := 0 else
  if not OverWaterAround(Point, MarginOverWater / 2) then
    Result := 0.3 else
  if not OverWaterAround(Point, MarginOverWater) then
    Result := 0.6 else
    Result := 1;
end;

type
  TGame = class
    class procedure MoveAllowed(Sender: TCastleSceneManager;
      var Allowed: boolean; const OldPosition, NewPosition: TVector3Single;
      const BecauseOfGravity: boolean);
  end;

class procedure TGame.MoveAllowed(Sender: TCastleSceneManager;
  var Allowed: boolean; const OldPosition, NewPosition: TVector3Single;
  const BecauseOfGravity: boolean);
var
  OldHeight, NewHeight: Single;
begin
  Allowed := Allowed and (not BecauseOfGravity);
  if Allowed then
  begin
    if (not OverWater(AvatarPositionFromCamera(NewPosition), NewHeight)) and
       (OverWater(AvatarPositionFromCamera(OldPosition), OldHeight) or
        (OldHeight > NewHeight)) then
      Allowed := false;
  end;
end;

function ColorFromHeight(Terrain: TTerrain; Height: Single): TVector3Single;
var
  I: Integer;
begin
  { scale height down by Amplitude, to keep nice colors regardless of Amplitude }
  if Terrain is TTerrainNoise then
    Height /= TTerrainNoise(Terrain).Amplitude;
  { some hacks to hit interesting colors }
  Height := Height  * 2000 - 1000;

  if Height < 0 then
    Result := Vector3Single(0.5, 0.5, 1) { light blue } else
  if Height < 500 then
    Result := Vector3Single(0, Height / 500, 0) { green } else
    Result := Vector3Single(Height / 500 - 1, 1, 0); { yellow }

  for I := 0 to 2 do
    Result[I] := Sqrt(Sin(Result[I] * 1.5));
end;

procedure ConfigureScene(const Scene: TCastleScene);
begin
  Scene.Spatial := [ssRendering, ssDynamicCollisions];
  Scene.ProcessEvents := true;
  Scene.DistanceCulling := VisibilityLimit;

  Scene.Attributes.WireframeEffect := weSilhouette;
  Scene.Attributes.WireframeColor := Vector3Single(0, 0, 0);
  Scene.Attributes.LineWidth := 10;
  Scene.Attributes.SilhouetteScale := 10.1;
  Scene.Attributes.SilhouetteBias := 0.2;
  // Scene.Attributes.Shaders := srAlways;
end;

var
  { publicly available just for debug, to adjust params visually }
  TerrainTransform: TTransformNode;

procedure LoadPart(const Part: TPart);
var
  PartName: string;

  { Load from a TTerrain data.
    @param RealSize is the size in X and Z in world space. }
  function LoadTerrainPart(const Terrain: TTerrain; const RealSize: Single = 31.33 * 3;
    const YShift: Single = -19): TCastleScene;
  var
    Node: TShapeNode;
    Root: TX3DRootNode;
    Texture: TImageTextureNode;
    TextureTransform: TTextureTransformNode;
  const
    Size = 3;
  begin
    Node := Terrain.CreateNode(1 shl 6 + 1, Size * 2,
      Vector2Single(-Size, Size), Vector2Single(-Size, Size), @ColorFromHeight);

    Texture := TImageTextureNode.Create('', '');
    Texture.FdUrl.Items.Add(ApplicationData('level/textures/sand.png'));
    Node.Appearance.FdTexture.Value := Texture;

    TextureTransform := TTextureTransformNode.Create('', '');
    TextureTransform.FdScale.Value := Vector2Single(10, 10);
    Node.Appearance.FdTextureTransform.Value := TextureTransform;

    TerrainTransform := TTransformNode.Create('', '');
    TerrainTransform.FdTranslation.Send(Vector3Single(
      -RealSize / 2, YShift,
      -RealSize / 2));
    TerrainTransform.FdScale.Send(Vector3Single(
      RealSize * 1/Size,
      RealSize * 1/Size,
      RealSize * 1/Size));
    TerrainTransform.FdChildren.Add(Node);

    Root := TX3DRootNode.Create('', '');
    Root.FdChildren.Add(TerrainTransform);
    Root.FdChildren.Add(Load3D(ApplicationData('level/' + PartName + '/part_final.x3dv')));

    Result := TCastleScene.Create(SceneManager);
    Result.Load(Root, true);
  end;

{
  function LoadIslandPart: TCastleScene;
  var
    Terrain: TTerrainImage;
  begin
    Terrain := TTerrainImage.Create;
    try
      Terrain.LoadImage(ApplicationData('level/lake/terrain.png'));
      Terrain.ImageHeightScale := 1;
      Terrain.ImageX1 := -3;
      Terrain.ImageY1 := -3;
      Terrain.ImageX2 :=  3;
      Terrain.ImageY2 :=  3;
      Result := LoadTerrainPart(Terrain, 40, -5);
    finally FreeAndNil(Terrain) end;
  end;
}

  function LoadLakePart: TCastleScene;
  var
    Terrain: TTerrainNoise;
  begin
    Terrain := TTerrainNoise.Create;
    try
      Terrain.Octaves := 4.25;
      Terrain.Smoothness := 2.35;
      Terrain.Heterogeneous := 0.22;
      Terrain.Amplitude := 0.75;
      Terrain.Frequency := 0.9;
      Terrain.Seed := 1550516520; //Random(High(LongInt)); Writeln('seed is ', Terrain.Seed);
      Result := LoadTerrainPart(Terrain);
    finally FreeAndNil(Terrain) end;
  end;

  function LoadStaticPart: TCastleScene;
  begin
    Result := TCastleScene.Create(SceneManager);
    Result.Load(ApplicationData('level/' + PartName + '/part_final.x3dv'));
  end;

var
  InitialPosition, InitialDirection, InitialUp, GravityUp: TVector3Single;
  NewBackground: TAbstractBackgroundNode;
begin
  FreeAndNil(CurrentPartScene);
  TerrainTransform := nil;

  PartName := PartNames[Part];

  case Part of
    pLake  : CurrentPartScene := LoadLakePart;
    // pIsland: CurrentPartScene := LoadIslandPart;
    else CurrentPartScene := LoadStaticPart;
  end;
  { Camera should not collide with 3D, only the avatar, which is done by special code in OnMoveAllowed }
  CurrentPartScene.Collides := false;

  PaintedEffect.Enabled := Part <> pCave;

  NewBackground := SceneManager.MainScene.RootNode.TryFindNodeByName(
    TAbstractBackgroundNode, 'Background' + PartName, false) as TAbstractBackgroundNode;
  if NewBackground <> nil then
  begin
    NewBackground.EventSet_bind.Send(true);
    WritelnLog('little_things', 'Found and bound background ' + NewBackground.NodeName);
  end;

  ConfigureScene(CurrentPartScene);
  SceneManager.Items.Add(CurrentPartScene);

  { do not use automatic MoveLimit from SceneManager.LoadLevel, it is not useful
    when we dynamically switch parts, and it doesn't make sense on pIsland part. }
  SceneManager.MoveLimit := EmptyBox3D;

  if CurrentPartScene.ViewpointStack.Top <> nil then
  begin
    CurrentPartScene.ViewpointStack.Top.GetView(InitialPosition, InitialDirection, InitialUp, GravityUp);
    Player.Camera.SetView(InitialPosition, InitialDirection, InitialUp);
  end;

  CurrentPart := Part;
  WritelnLog('little_things', 'Switched to part ' + PartNames[Part]);

  DogTransform := CurrentPartScene.RootNode.TryFindNodeByName(
    TTransformNode, 'DogTransform', false) as TTransformNode;
  if DogTransform = nil then
    OnWarning(wtMajor, 'DogTransform', 'DogTransform not found on part ' + PartName);

{
  if Part = pCave then
  begin
    CreatureResource := Resources.FindName('Spider') as TCreatureResource;
    CreatureResource.CreateCreature(SceneManager.Items,
      Vector3Single(-36.133621215820313, 5.122468948364258, 126.4378662109375),
      Vector3Single(0.45594298839569092, -0.24616692960262299, -0.85528826713562012)
    );
  end;}
end;

procedure StartGame;
var
  Avatar: TCastlePrecalculatedAnimation;
begin
  SeedDirection := Random(High(LongInt));
  SeedSpeed := Random(High(LongInt));

  Player := TPlayer.Create(SceneManager);
  Player.Camera.MouseLook := true;
  Player.Camera.RotationHorizontalPivot := 5;
//  Player.Flying := true; // no gravity
  SceneManager.Items.Add(Player);
  SceneManager.Player := Player;
  SceneManager.OnMoveAllowed := @TGame(nil).MoveAllowed;

  PlayerInput_LeftStrafe.MakeClear;
  PlayerInput_RightStrafe.MakeClear;
  PlayerInput_GravityUp.MakeClear;
  PlayerInput_Jump.MakeClear;
  PlayerInput_Crouch.MakeClear;

  SceneManager.LoadLevel('water');
  SceneManager.UseGlobalLights := true;
  { Camera should not collide with 3D, only the avatar, which is done by special code in OnMoveAllowed }
  SceneManager.MainScene.Collides := false;
  WaterTransform := SceneManager.MainScene.RootNode.FindNodeByName(
    TTransformNode, 'WaterTransform', false) as TTransformNode;
  if SceneManager.MainScene.NavigationInfoStack.Top <> nil then
  begin
    VisibilityLimit := SceneManager.MainScene.NavigationInfoStack.Top.FdVisibilityLimit.Value;
    WritelnLog('little_things', 'Using VisibilityLimit %f', [VisibilityLimit]);
  end;
  PaintedEffect := SceneManager.MainScene.RootNode.TryFindNodeByName(
    TScreenEffectNode, 'PaintedEffect', false) as TScreenEffectNode;

  AvatarTransform := T3DTransform.Create(SceneManager);
  AvatarTransform.Scale := Vector3Single(0.3, 0.3, 0.3); // scale in code, scaling animation with cloth in Blender causes problems
  SceneManager.Items.Add(AvatarTransform);

  Avatar := TCastlePrecalculatedAnimation.Create(SceneManager);
  Avatar.LoadFromFile(ApplicationData('avatar/avatar.kanim'), false, false);
  { it's easier to set TimeXxx in code,
    instead of manually editing kanim each time after exporting from Blender }
  Avatar.TimeBackwards := true;
  Avatar.TimeLoop := true;
  Avatar.TimePlayingSpeed := 10;
  AvatarTransform.Add(Avatar);

  DefaultMoveSpeed := Player.Camera.MoveSpeed;

  LoadPart(pForest);
end;

procedure GameUpdate(const SecondsPassed: Single);

  procedure Wind;
  var
    WindMove, OldPosition, NewPosition: TVector3Single;
    WindDirectionAngle: Single;
    WindDirection: TVector3Single;
    WindSpeed: Single;
    S, C: Extended;
  begin
    WindTime += SecondsPassed;
    WindDirectionAngle := BlurredInterpolatedNoise2D_Spline(WindTime * 2, 0, SeedDirection) * 2 * Pi;
    SinCos(WindDirectionAngle, S, C);
    WindDirection := Vector3Single(S, 0, C);
    WindSpeed := 0.1 + BlurredInterpolatedNoise2D_Spline(WindTime / 2, 0, SeedSpeed) * 1.0;

    WindMove := WindDirection * WindSpeed * SecondsPassed;
    OldPosition := Player.Camera.Position;
    NewPosition := OldPosition + WindMove;

    if OverWater(AvatarPositionFromCamera(OldPosition)) and
       OverWater(AvatarPositionFromCamera(NewPosition)) then
      Player.Camera.Position := NewPosition;
  end;

const
  MoveSpeedChangeSpeed = 5;
  DistanceToDogToFinish = 10.0;
var
  MoveSpeedTarget: Single;
begin
  WaterTransform.FdTranslation.Send(Vector3Single(
    Player.Position[0], WaterTransform.FdTranslation.Value[1],
    Player.Position[2]));

  { we use DirectionInGravityPlane, not Direction, to never make avatar non-horizontal }
  AvatarTransform.Rotation :=
    CamDirUp2Orient(Player.Camera.DirectionInGravityPlane, SceneManager.GravityUp);

  MoveSpeedTarget := DefaultMoveSpeed * OverWaterFactor(AvatarTransform.Translation);
  if MoveSpeedTarget > Player.Camera.MoveSpeed then
    Player.Camera.MoveSpeed := Min(Player.Camera.MoveSpeed + SecondsPassed * MoveSpeedChangeSpeed, MoveSpeedTarget) else
  if MoveSpeedTarget < Player.Camera.MoveSpeed then
    Player.Camera.MoveSpeed := Max(Player.Camera.MoveSpeed - SecondsPassed * MoveSpeedChangeSpeed, MoveSpeedTarget);

  //Writeln(Player.Camera.MoveSpeed:1:10, ' for ', VectorToNiceStr(AvatarTransform.Translation));

  Wind;

  AvatarTransform.Translation := AvatarPositionFromCamera(Player.Camera.Position);

  { make sure CurrentPartScene knows about current camera.
    By default, only MainScene knows about it, and we want to pass it to CurrentPartScene
    to use CurrentPartScene.DistanceCulling. }
  CurrentPartScene.CameraChanged(SceneManager.Camera, []);

  if (DogTransform <> nil) and
     (PointsDistanceSqr(DogTransform.FdTranslation.Value, Player.Camera.Position) <
      Sqr(DistanceToDogToFinish)) then
  begin
    if CurrentPart = High(CurrentPart) then
      LoadPart(Low(TPart)) else
      LoadPart(Succ(CurrentPart));
  end;
end;

procedure GameRender;

  procedure VisualizeRayDown(Point: TVector3Single);
  begin
    Point[SceneManager.Items.GravityCoordinate] := -HeightOverAvatar;
//    Writeln(VectorToNiceStr(Point));
    glVertexv(Point);

    Point[SceneManager.Items.GravityCoordinate] := +HeightOverAvatar;
//    Writeln(VectorToNiceStr(Point));
    glVertexv(Point);

    {glDrawBox3DWire(Box3D(
      Point,
      Point - Vector3Single(0, 2 * HeightOverEverything, 0)));}
  end;

var
  Point, Side: TVector3Single;
  Margin: Single;
begin
  {$ifndef OpenGLES} // TODO-es
  { TODO: why is this not visible with screen effect visible? }
  if RenderDebug3D then
  begin
    glLoadMatrix(RenderingCamera.Matrix);
    glPushAttrib(GL_ENABLE_BIT or GL_LIGHTING_BIT);
      GLEnableTexture(etNone);
      glDisable(GL_LIGHTING);
      glDisable(GL_CULL_FACE); { saved by GL_ENABLE_BIT }
      glDisable(GL_COLOR_MATERIAL); { saved by GL_ENABLE_BIT }
      glDisable(GL_ALPHA_TEST); { saved by GL_ENABLE_BIT }
      glDisable(GL_FOG); { saved by GL_ENABLE_BIT }
      glEnable(GL_DEPTH_TEST);
      CurrentProgram := nil;

      glColorv(Black);

      glBegin(GL_LINES);
        VisualizeRayDown(Player.Camera.Position);

        Point := AvatarPositionFromCamera(Player.Camera.Position);
        Side := VectorProduct(Player.Camera.DirectionInGravityPlane, SceneManager.GravityUp);

        VisualizeRayDown(Point);

        Margin := MarginOverWater;

        VisualizeRayDown(Point + Player.Camera.DirectionInGravityPlane * Margin);
        VisualizeRayDown(Point + Player.Camera.DirectionInGravityPlane * Margin + Side * Margin);
        VisualizeRayDown(Point + Player.Camera.DirectionInGravityPlane * Margin - Side * Margin);
        VisualizeRayDown(Point + Player.Camera.DirectionInGravityPlane * Margin + Side * Margin / 2);
        VisualizeRayDown(Point + Player.Camera.DirectionInGravityPlane * Margin - Side * Margin / 2);

        VisualizeRayDown(Point - Player.Camera.DirectionInGravityPlane * Margin * 2);
        VisualizeRayDown(Point - Player.Camera.DirectionInGravityPlane * Margin * 2 + Side * Margin);
        VisualizeRayDown(Point - Player.Camera.DirectionInGravityPlane * Margin * 2 - Side * Margin);

        Margin := MarginOverWater / 2;

        VisualizeRayDown(Point + Player.Camera.DirectionInGravityPlane * Margin);
        VisualizeRayDown(Point + Player.Camera.DirectionInGravityPlane * Margin + Side * Margin);
        VisualizeRayDown(Point + Player.Camera.DirectionInGravityPlane * Margin - Side * Margin);
        VisualizeRayDown(Point + Player.Camera.DirectionInGravityPlane * Margin + Side * Margin / 2);
        VisualizeRayDown(Point + Player.Camera.DirectionInGravityPlane * Margin - Side * Margin / 2);
      glEnd();
    glPopAttrib();
  end;
  {$endif}
end;

procedure GamePress(const Event: TInputPressRelease);
var
  Pos, Dir, Up, GravityUp: TVector3Single;
begin
  if Event.IsKey(K_1) then
    CurrentPartScene.Attributes.SilhouetteScale := CurrentPartScene.Attributes.SilhouetteScale - 0.1;
  if Event.IsKey(K_2) then
    CurrentPartScene.Attributes.SilhouetteScale := CurrentPartScene.Attributes.SilhouetteScale + 0.1;
  if Event.IsKey(K_3) then
    CurrentPartScene.Attributes.SilhouetteBias := CurrentPartScene.Attributes.SilhouetteBias - 0.1;
  if Event.IsKey(K_4) then
    CurrentPartScene.Attributes.SilhouetteBias := CurrentPartScene.Attributes.SilhouetteBias + 0.1;
  // Writeln(CurrentPartScene.Attributes.SilhouetteScale:1:10);
  // Writeln(CurrentPartScene.Attributes.SilhouetteBias:1:10);
  if Event.IsKey(K_5) then
  begin
    SceneManager.Camera := SceneManager.CreateDefaultCamera;
    (SceneManager.Camera as TUniversalCamera).NavigationType := ntExamine;
  end;
  if Event.IsKey(K_6) then
  begin
    if CurrentPart = High(CurrentPart) then
      LoadPart(Low(TPart)) else
      LoadPart(Succ(CurrentPart));
  end;
  if Event.IsKey(K_7) then
  begin
    InitializeLog;
    Player.Camera.GetView(Pos, Dir, Up, GravityUp);
    WritelnLog('Camera', MakeCameraStr(cvVrml2_X3d, false, Pos, Dir, Up, GravityUp));
  end;
  if Event.IsKey(K_8) then
    RenderDebug3D := not RenderDebug3D;

  if Event.IsKey(K_9) then
  begin
    TerrainTransform.FdScale.Value -= Vector3Single(0.5, 0.5, 0.5);
    TerrainTransform.FdScale.Changed;
    Writeln(VectorToNiceStr(TerrainTransform.FdScale.Value));
  end;
  if Event.IsKey(K_0) then
  begin
    TerrainTransform.FdScale.Value += Vector3Single(0.5, 0.5, 0.5);
    TerrainTransform.FdScale.Changed;
    Writeln(VectorToNiceStr(TerrainTransform.FdScale.Value));
  end;
  if Event.IsKey(K_P) then
  begin
    TerrainTransform.FdTranslation.Value[1] -= 0.5;
    TerrainTransform.FdTranslation.Changed;
    Writeln(FloatToNiceStr(TerrainTransform.FdTranslation.Value[1]));
  end;
  if Event.IsKey(K_O) then
  begin
    TerrainTransform.FdTranslation.Value[1] += 0.5;
    TerrainTransform.FdTranslation.Changed;
    Writeln(FloatToNiceStr(TerrainTransform.FdTranslation.Value[1]));
  end;
  if Event.IsKey(K_F5) then
  begin
    Window.SaveScreen(FileNameAutoInc(ApplicationName + '_screen_%d.png'));
  end;
end;

end.
