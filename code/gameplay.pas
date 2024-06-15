{
  Copyright 2014-2022 Michalis Kamburelis.

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

uses CastleScene, CastleTransform, X3DNodes, CastlePlayer, CastleLevels,
  CastleKeysMouse, CastleUIControls, CastleApplicationProperties;

type
  TPart = (pForest, pCave, pLake, pIsland);
const
  PartNames: array [TPart] of string = ('forest', 'cave', 'lake', 'island');

procedure LoadPart(const Part: TPart);

procedure StartGame;
procedure GamePress(Container: TUIContainer; const Event: TInputPressRelease);

var
  UseDebugPart: Boolean = false;
  DebugPart: TPart = pIsland;

function EnableDebugKeys(Container: TUIContainer): Boolean;

implementation

uses SysUtils, CastleVectors, CastleLog,
  CastleWindow, CastleResources, CastleTerrain, CastleCameras, CastleFilesUtils,
  Math, CastleSceneCore, CastleBoxes, CastleTimeUtils,
  CastleGL, CastleGLUtils, CastleGLShaders, Game, GamePlayer, CastleGLVersion,
  CastleUtils, X3DLoad, X3DCameraUtils, CastleRenderOptions,
  CastleSceneManager, CastleColors, CastleInternalNoise, CastleRenderContext,
  CastleControls, CastleFrustum, CastleRectangles, CastleViewport;

type
  { TODO: Remake as TUIState descendant, use TUIState for title and game states. }
  TGameUI = class(TCastleUserInterface)
    procedure Update(const SecondsPassed: Single;
      var HandleInput: Boolean); override;
    procedure BeforeRender; override;
  end;

  TGameDebug3D = class(TCastleTransform)
    function LocalBoundingBox: TBox3D; override;
    procedure LocalRender(const Params: TRenderParams); override;
  end;

var
  DefaultMoveSpeed: Single;
  VisibilityLimit: Single;
  RenderDebug3D: Boolean;
  GpuATI: Boolean;

  CurrentPart: TPart;
  CurrentPartTransform: TCastleTransform;
  CurrentPartScene: TCastleScene; // sometimes equal to CurrentPartTransform, sometimes child of it

  WaterTransform: TTransformNode;
  DogTransform: TTransformNode;
  PaintedEffect: TScreenEffectNode;
  AvatarTransform: TCastleTransform;

  WindTime: TFloatTime;
  SeedDirection: Cardinal;
  SeedSpeed: Cardinal;

  GameDebug3D: TGameDebug3D;

const
  HeightOverAvatar = 2.0; //< do not make it ultra-large, to allow swimming under passages
  WaterHeight = 0.0;
  MarginOverWater = 0.5;

  PartConfig: array [TPart] of record
    PaintedEffect: Boolean;
  end = (
    { forest } (PaintedEffect: true),
    { cave   } (PaintedEffect: false),
    { lake   } (PaintedEffect: true),
    { island } (PaintedEffect: false)
  );

{ routines ------------------------------------------------------------------- }

function AvatarPositionFromCamera(const CameraPosition: TVector3): TVector3;
begin
  Result := CameraPosition +
    Player.WalkNavigation.DirectionInGravityPlane * Player.WalkNavigation.RotationHorizontalPivot;
  Result.Items[SceneManager.Items.GravityCoordinate] := WaterHeight; // constant height on the water
end;

function OverWater(Point: TVector3; out Height: Single): Boolean;
var
  Collision: TRayCollision;
  SavedMainSceneExists, SavedAvatarExists: Boolean;
begin
  Point.Items[SceneManager.Items.GravityCoordinate] := HeightOverAvatar;
  SavedMainSceneExists := SceneManager.Items.MainScene.Exists;
  SceneManager.Items.MainScene.Exists := false; // do not hit water surface
  SavedAvatarExists := AvatarTransform.Exists;
  AvatarTransform.Exists := false; // do not hit avatar
  try
    Collision := SceneManager.Items.WorldRay(Point, -SceneManager.Camera.GravityUp);
    Result := (Collision = nil) or
              (Collision.First.Point[SceneManager.Items.GravityCoordinate] < WaterHeight);
    if not Result then
      Height := Collision.First.Point[SceneManager.Items.GravityCoordinate];
    FreeAndNil(Collision);
  finally
    SceneManager.Items.MainScene.Exists := SavedMainSceneExists;
    AvatarTransform.Exists := SavedAvatarExists;
  end;
end;

function OverWater(Point: TVector3): Boolean;
var
  Height: Single;
begin
  Result := OverWater(Point, Height { ignore });
end;

function OverWaterAround(const Point: TVector3; const Margin: Single;
  out Height: Single): Boolean;
var
  Side: TVector3;
begin
  Side := TVector3.CrossProduct(Player.WalkNavigation.DirectionInGravityPlane, SceneManager.Camera.GravityUp);
  Result :=
    { to protect forward movement }
    OverWater(Point + Player.WalkNavigation.DirectionInGravityPlane * Margin                    , Height) and
    OverWater(Point + Player.WalkNavigation.DirectionInGravityPlane * Margin + Side * Margin    , Height) and
    OverWater(Point + Player.WalkNavigation.DirectionInGravityPlane * Margin - Side * Margin    , Height) and
    OverWater(Point + Player.WalkNavigation.DirectionInGravityPlane * Margin + Side * Margin / 2, Height) and
    OverWater(Point + Player.WalkNavigation.DirectionInGravityPlane * Margin - Side * Margin / 2, Height) and

    { to protect backward movement }
    OverWater(Point - Player.WalkNavigation.DirectionInGravityPlane * Margin * 2                , Height) and
    OverWater(Point - Player.WalkNavigation.DirectionInGravityPlane * Margin * 2 + Side * Margin, Height) and
    OverWater(Point - Player.WalkNavigation.DirectionInGravityPlane * Margin * 2 - Side * Margin, Height);
    // OverWater(Point + Vector3(-Margin, 0, -Margin)) and
    // OverWater(Point + Vector3(-Margin, 0,  Margin)) and
    // OverWater(Point + Vector3( Margin, 0, -Margin)) and
    // OverWater(Point + Vector3( Margin, 0,  Margin)) and

    // OverWater(Point + Vector3(-Margin, 0,       0)) and
    // OverWater(Point + Vector3( Margin, 0,       0)) and
    // OverWater(Point + Vector3(      0, 0, -Margin)) and
    // OverWater(Point + Vector3(      0, 0,  Margin));
end;

function OverWaterAround(const Point: TVector3; const Margin: Single): Boolean;
var
  Height: Single;
begin
  Result := OverWaterAround(Point, Margin, Height { ignore });
end;

function OverWaterFactor(const Point: TVector3): Single;
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
    class function MoveAllowed(const Navigation: TCastleNavigation;
      const OldPos, ProposedNewPos: TVector3; out NewPos: TVector3;
      const  Radius: Single; const BecauseOfGravity: Boolean): Boolean;
  end;

class function TGame.MoveAllowed(const Navigation: TCastleNavigation;
  const OldPos, ProposedNewPos: TVector3; out NewPos: TVector3;
  const  Radius: Single; const BecauseOfGravity: Boolean): Boolean;
var
  OldHeight, NewHeight: Single;
begin
  NewPos := ProposedNewPos;
  Result := not BecauseOfGravity;
  if Result then
  begin
    if (not OverWaterAround(AvatarPositionFromCamera(NewPos), MarginOverWater, NewHeight)) and
       (OverWaterAround(AvatarPositionFromCamera(OldPos), MarginOverWater, OldHeight) or
        (OldHeight > NewHeight)) then
      Result := false;
  end;
end;

procedure ConfigureScene(const Scene: TCastleScene);
begin
  Scene.Spatial := [ssRendering, ssDynamicCollisions];
  Scene.ProcessEvents := true;
  Scene.DistanceCulling := VisibilityLimit;

  Scene.RenderOptions.WireframeEffect := weSilhouette;
  Scene.RenderOptions.WireframeColor := Vector3(0, 0, 0);
  Scene.RenderOptions.LineWidth := 10;
  Scene.RenderOptions.SilhouetteScale := 10.1;
  Scene.RenderOptions.SilhouetteBias := 0.2;
  // Scene.RenderOptions.Shaders := srAlways;
end;

procedure LoadPart(const Part: TPart);
var
  PartName: string;

  { Load a terrain part, with some non-terrain scene on top.
    @param RealSize is the size in X and Z in world space. }
  function LoadTerrainPart(const TerrainData: TCastleTerrainData;
    const RealSize: Single = 31.33 * 3;
    const YShift: Single = -19): TCastleTransform;
  var
    Terrain: TCastleTerrain;
    NonTerrainScene: TCastleScene;
    CompleteTransform: TCastleTransform;
  const
    Size = 3;
    BestSubdivisions = 1 shl 6 + 1;
  begin
    CompleteTransform := TCastleTransform.Create(SceneManager);

    Terrain := TCastleTerrain.Create(SceneManager);
    // TODO: We use same settings for all 4 layers, we don't really utilize layers here for now
    Terrain.Layer1.Texture := 'castle-data:/level/textures/sand.png';
    Terrain.Layer2.Texture := 'castle-data:/level/textures/sand.png';
    Terrain.Layer3.Texture := 'castle-data:/level/textures/sand.png';
    Terrain.Layer4.Texture := 'castle-data:/level/textures/sand.png';
    Terrain.Layer1.Color := YellowRGB;
    Terrain.Layer2.Color := YellowRGB;
    Terrain.Layer3.Color := YellowRGB;
    Terrain.Layer4.Color := YellowRGB;
    Terrain.Layer1.UvScale := 10;
    Terrain.Layer2.UvScale := 10;
    Terrain.Layer3.UvScale := 10;
    Terrain.Layer4.UvScale := 10;
    Terrain.Subdivisions := Vector2(BestSubdivisions, BestSubdivisions);
    Terrain.Size := Vector2(Size * 2, Size * 2);
    Terrain.Collides := false; // Just like ConfigureScene
    Terrain.Data := TerrainData;

    { TODO: Why the terrain randomly blinks in-out? }
    Terrain.Translation := Vector3(
      -RealSize / 2, YShift,
      -RealSize / 2);
    Terrain.Scale := Vector3(
      RealSize * 1/Size,
      RealSize * 1/Size,
      RealSize * 1/Size);
    CompleteTransform.Add(Terrain);

    NonTerrainScene := TCastleScene.Create(SceneManager);
    NonTerrainScene.Load(ApplicationData('level/' + PartName + '/part_final.x3dv'));
    CompleteTransform.Add(NonTerrainScene);

    Result := CompleteTransform;
  end;

{
  function LoadIslandPart: TCastleScene;
  var
    Terrain: TTerrainImage;
  begin
    Terrain := TTerrainImage.Create;
    try
      Terrain.LoadImage('castle-data:/level/lake/terrain.png');
      Terrain.ImageHeightScale := 1;
      Terrain.ImageX1 := -3;
      Terrain.ImageY1 := -3;
      Terrain.ImageX2 :=  3;
      Terrain.ImageY2 :=  3;
      Result := LoadTerrainPart(Terrain, 40, -5);
    finally FreeAndNil(Terrain) end;
  end;
}

  function LoadLakePart: TCastleTransform;
  var
    Terrain: TCastleTerrainNoise;
  begin
    Terrain := TCastleTerrainNoise.Create(SceneManager);
    Terrain.Octaves := 4.25;
    Terrain.Smoothness := 2.35;
    Terrain.Heterogeneous := 0.22;
    Terrain.Amplitude := 0.75;
    Terrain.Frequency := 0.9;
    Terrain.Seed := 1073933886; // Random(High(LongInt)); Writeln('seed is ', Terrain.Seed);

    Result := LoadTerrainPart(Terrain);
  end;

  function LoadStaticPart: TCastleScene;
  begin
    Result := TCastleScene.Create(SceneManager);
    Result.Load(ApplicationData('level/' + PartName + '/part_final.x3dv'));
  end;

var
  InitialPosition, InitialDirection, InitialUp, GravityUp: TVector3;
  NewBackground: TAbstractBackgroundNode;
begin
  FreeAndNil(CurrentPartTransform);
  // TODO: Free also CurrentPartTransform children, in case we had 2 children loaded by LoadLakePart

  PartName := PartNames[Part];

  case Part of
    pLake:
      begin
        CurrentPartTransform := LoadLakePart;
        CurrentPartScene := CurrentPartTransform[1] as TCastleScene; // TODO: Assuming what LoadTerrainPart does
      end;
    else
      begin
        CurrentPartTransform := LoadStaticPart;
        CurrentPartScene := CurrentPartTransform as TCastleScene;
      end;
  end;
  { Camera should not collide with 3D, only the avatar, which is done by special code in OnMoveAllowed }
  CurrentPartTransform.Collides := false;

  PaintedEffect.Enabled := PartConfig[Part].PaintedEffect;

  NewBackground := SceneManager.Items.MainScene.RootNode.TryFindNodeByName(
    TAbstractBackgroundNode, 'Background' + PartName, false) as TAbstractBackgroundNode;
  if NewBackground <> nil then
  begin
    NewBackground.EventSet_bind.Send(true);
    WritelnLog('little_things', 'Found and bound background ' + NewBackground.X3DName);
  end;

  ConfigureScene(CurrentPartScene);
  SceneManager.Items.Add(CurrentPartTransform);

  { do not use automatic MoveLimit from SceneManager.LoadLevel, it is not useful
    when we dynamically switch parts, and it doesn't make sense on pIsland part. }
  SceneManager.Items.MoveLimit := TBox3D.Empty;

  if CurrentPartScene.ViewpointStack.Top <> nil then
  begin
    CurrentPartScene.ViewpointStack.Top.GetView(InitialPosition, InitialDirection, InitialUp, GravityUp);
    SceneManager.Camera.SetView(InitialPosition, InitialDirection, InitialUp);
  end;

  CurrentPart := Part;
  WritelnLog('little_things', 'Switched to part ' + PartNames[Part]);

  DogTransform := CurrentPartScene.RootNode.TryFindNodeByName(
    TTransformNode, 'DogTransform', false) as TTransformNode;
  if DogTransform = nil then
    WritelnWarning('DogTransform', 'DogTransform not found on part ' + PartName);

{
  if Part = pCave then
  begin
    CreatureResource := Resources.FindName('Spider') as TCreatureResource;
    CreatureResource.CreateCreature(SceneManager.Items,
      Vector3(-36.133621215820313, 5.122468948364258, 126.4378662109375),
      Vector3(0.45594298839569092, -0.24616692960262299, -0.85528826713562012)
    );
  end;}
end;

procedure StartGame;
var
  Avatar: TCastleScene;
  GameUI: TGameUI;
  TouchNavigation: TCastleTouchNavigation;
begin
  TitleScreen := false;
  GpuATI := (GLVersion.VendorType = gvATI) or (Pos('AMD', GLVersion.Renderer) <> -1);
  if GpuATI then
    WritelnLog('GPU', 'Silhouette glPolygonOffset will be adjusted faster for ATI GPU');

  SeedDirection := Random(High(LongInt));
  SeedSpeed := Random(High(LongInt));

  Player.Blocked := false;

  PlayerInput_LeftStrafe.MakeClear(true);
  PlayerInput_RightStrafe.MakeClear(true);
  PlayerInput_GravityUp.MakeClear(true);
  PlayerInput_Jump.MakeClear(true);
  PlayerInput_Crouch.MakeClear(true);
  { Disable some default input shortcuts defined by CastleSceneManager.
    They will not do anything if we don't use the related functionality
    (if we don't put anything into the default Player.Inventory),
    but it's a little cleaner to still disable them to avoid spurious
    warnings like "No weapon equipped" on each press of Ctrl key. }
  PlayerInput_Attack.MakeClear(true);
  PlayerInput_InventoryShow.MakeClear(true);
  PlayerInput_InventoryPrevious.MakeClear(true);
  PlayerInput_InventoryNext.MakeClear(true);
  PlayerInput_UseItem.MakeClear(true);
  PlayerInput_DropItem.MakeClear(true);
  PlayerInput_CancelFlying.MakeClear(true);

  SceneManager.LoadLevel('water');
  Player.WalkNavigation.OnMoveAllowed := @TGame(nil).MoveAllowed;
  SceneManager.UseGlobalLights := true;
  { Camera should not collide with 3D, only the avatar, which is done by special code in OnMoveAllowed }
  SceneManager.Items.MainScene.Collides := false;
  WaterTransform := SceneManager.Items.MainScene.RootNode.FindNodeByName(
    TTransformNode, 'WaterTransform', false) as TTransformNode;
  if SceneManager.Items.MainScene.NavigationInfoStack.Top <> nil then
  begin
    VisibilityLimit := SceneManager.Items.MainScene.NavigationInfoStack.Top.VisibilityLimit;
    WritelnLog('little_things', 'Using VisibilityLimit %f', [VisibilityLimit]);
  end;
  PaintedEffect := SceneManager.Items.MainScene.RootNode.TryFindNodeByName(
    TScreenEffectNode, 'PaintedEffect', false) as TScreenEffectNode;

  AvatarTransform := TCastleTransform.Create(SceneManager);
  AvatarTransform.Scale := Vector3(0.3, 0.3, 0.3); // scale in code, scaling animation with cloth in Blender causes problems
  SceneManager.Items.Add(AvatarTransform);

  Avatar := TCastleScene.Create(SceneManager);
  Avatar.Load('castle-data:/avatar/avatar.kanim');
  Avatar.ProcessEvents := true;
  Avatar.PlayAnimation('animation', true);
  Avatar.TimePlayingSpeed := 10;
  AvatarTransform.Add(Avatar);

  { Adjust navigation based on ApplicationProperties.TouchDevice.
    It is automatically set based on mobile/not,
    you can also manually force it to test e.g. mobile UI on desktop. }
  //ApplicationProperties.TouchDevice := true; // uncomment to test mobile UI on desktop

  TouchNavigation := TCastleTouchNavigation.Create(SceneManager);
  TouchNavigation.Exists := ApplicationProperties.TouchDevice;
  { Do not use AutoTouchInterface, as we pretend we're flying for a hacky
    3rd-person camera, so AutoTouchInterface would cause using TouchInterface for flying. }
  TouchNavigation.TouchInterface := tiWalkRotate;
  TouchNavigation.FullSize := true;
  TouchNavigation.Viewport := SceneManager;
  SceneManager.InsertFront(TouchNavigation);

  Player.EnableCameraDragging := ApplicationProperties.TouchDevice;

  Player.WalkNavigation.MouseLook := not ApplicationProperties.TouchDevice;

  DefaultMoveSpeed := Player.WalkNavigation.MoveSpeed;

  if UseDebugPart then
    LoadPart(DebugPart) else
    LoadPart(Low(TPart));

  GameUI := TGameUI.Create(Application);
  Window.Controls.InsertFront(GameUI);

  GameDebug3D := TGameDebug3D.Create(Application);
  GameDebug3D.Exists := RenderDebug3D;
  GameDebug3D.Collides := false;
  SceneManager.Items.Add(GameDebug3D);
end;

procedure GamePress(Container: TUIContainer; const Event: TInputPressRelease);

  procedure ReportPolygonOffset;
  begin
    WritelnLog('GPU', 'SilhouetteScale: %f, SilhouetteBias: %f',
      [ CurrentPartScene.RenderOptions.SilhouetteScale,
        CurrentPartScene.RenderOptions.SilhouetteBias]);
  end;

var
  PolygonOffsetFactor: Single;
begin
  if EnableDebugKeys(Container) then
  begin
    if GpuATI then
      PolygonOffsetFactor := 1.0 else
      PolygonOffsetFactor := 0.1;
    if Event.IsKey(key1) then
    begin
      CurrentPartScene.RenderOptions.SilhouetteScale := CurrentPartScene.RenderOptions.SilhouetteScale - PolygonOffsetFactor;
      ReportPolygonOffset;
    end;
    if Event.IsKey(key2) then
    begin
      CurrentPartScene.RenderOptions.SilhouetteScale := CurrentPartScene.RenderOptions.SilhouetteScale + PolygonOffsetFactor;
      ReportPolygonOffset;
    end;
    if Event.IsKey(key3) then
    begin
      CurrentPartScene.RenderOptions.SilhouetteBias := CurrentPartScene.RenderOptions.SilhouetteBias - PolygonOffsetFactor;
      ReportPolygonOffset;
    end;
    if Event.IsKey(key4) then
    begin
      CurrentPartScene.RenderOptions.SilhouetteBias := CurrentPartScene.RenderOptions.SilhouetteBias + PolygonOffsetFactor;
      ReportPolygonOffset;
    end;
    if Event.IsKey(key5) then
    begin
      SceneManager.NavigationType := ntExamine;
    end;
    if Event.IsKey(key6) then
    begin
      if CurrentPart = High(CurrentPart) then
        LoadPart(Low(TPart)) else
        LoadPart(Succ(CurrentPart));
    end;
    if Event.IsKey(key8) then
    begin
      RenderDebug3D := not RenderDebug3D;
      GameDebug3D.Exists := RenderDebug3D;
    end;
  end;

  if Event.IsKey(keyF5) then
    Window.SaveScreen(FileNameAutoInc(ApplicationName + '_screen_%d.png'));
  if Event.IsKey(keyEscape) then
    Window.Close;
end;

function EnableDebugKeys(Container: TUIContainer): Boolean;
begin
  { debug keys only with Ctrl }
  Result := Container.Pressed[keyCtrl];
end;

{ TGameUI -------------------------------------------------------------------- }

procedure TGameUI.Update(const SecondsPassed: Single;
  var HandleInput: Boolean);

  procedure Wind;
  var
    WindMove, OldPosition, NewPosition: TVector3;
    WindDirectionAngle: Single;
    WindDirection: TVector3;
    WindSpeed: Single;
    S, C: Extended;
  begin
    WindTime := WindTime + SecondsPassed;
    WindDirectionAngle := BlurredInterpolatedNoise2D_Spline(WindTime * 2, 0, SeedDirection) * 2 * Pi;
    SinCos(WindDirectionAngle, S, C);
    WindDirection := Vector3(S, 0, C);
    WindSpeed := 0.1 + BlurredInterpolatedNoise2D_Spline(WindTime / 2, 0, SeedSpeed) * 1.0;

    WindMove := WindDirection * WindSpeed * SecondsPassed;
    OldPosition := SceneManager.Camera.Position;
    NewPosition := OldPosition + WindMove;

    if OverWaterAround(AvatarPositionFromCamera(OldPosition), MarginOverWater) and
       OverWaterAround(AvatarPositionFromCamera(NewPosition), MarginOverWater) then
      SceneManager.Camera.Position := NewPosition;
  end;

const
  MoveSpeedChangeSpeed = 5;
  DistanceToDogToFinish = 10.0;
var
  MoveSpeedTarget: Single;
begin
  inherited;

  MoveSpeedTarget := DefaultMoveSpeed * OverWaterFactor(AvatarTransform.Translation);
  if MoveSpeedTarget > Player.WalkNavigation.MoveSpeed then
    Player.WalkNavigation.MoveSpeed := Min(Player.WalkNavigation.MoveSpeed + SecondsPassed * MoveSpeedChangeSpeed, MoveSpeedTarget) else
  if MoveSpeedTarget < Player.WalkNavigation.MoveSpeed then
    Player.WalkNavigation.MoveSpeed := Max(Player.WalkNavigation.MoveSpeed - SecondsPassed * MoveSpeedChangeSpeed, MoveSpeedTarget);

  //Writeln(Player.WalkNavigation.MoveSpeed:1:10, ' for ', AvatarTransform.Translation.ToString);

  Wind;

  if (DogTransform <> nil) and
     (PointsDistanceSqr(DogTransform.Translation, SceneManager.Camera.Position) <
      Sqr(DistanceToDogToFinish)) then
  begin
    if CurrentPart = High(CurrentPart) then
      LoadPart(Low(TPart)) else
      LoadPart(Succ(CurrentPart));
  end;
end;

procedure TGameUI.BeforeRender;
begin
  inherited;

  { These need to be done in BeforeRender, not in Update,
    otherwise there will be a visible delay between camera move/rotations
    and the avatar move/rotations. }

  WaterTransform.Translation := Vector3(
    Player.Translation[0], WaterTransform.Translation[1],
    Player.Translation[2]);

  { we use DirectionInGravityPlane, not Direction, to never make avatar non-horizontal }
  AvatarTransform.Rotation :=
    OrientationFromDirectionUp(Player.WalkNavigation.DirectionInGravityPlane, SceneManager.Camera.GravityUp);

  AvatarTransform.Translation := AvatarPositionFromCamera(SceneManager.Camera.Position);
end;

{ TGameDebug3D --------------------------------------------------------------- }

function TGameDebug3D.LocalBoundingBox: TBox3D;
begin
  Result := SceneManager.Items.MainScene.BoundingBox;
end;

procedure TGameDebug3D.LocalRender(const Params: TRenderParams);

  {$ifdef TODO_OLD_GL_RENDERING} // TODO rework to use TCastleRenderUnlit
  procedure VisualizeRayDown(Point: TVector3);
  begin
    Point.Items[SceneManager.Items.GravityCoordinate] := -HeightOverAvatar;
//    Writeln(Point.ToString);
    glVertexv(Point);

    Point.Items[SceneManager.Items.GravityCoordinate] := +HeightOverAvatar;
//    Writeln(Point.ToString);
    glVertexv(Point);

    {glDrawBox3DWire(Box3D(
      Point,
      Point - Vector3(0, 2 * HeightOverEverything, 0)));}
  end;
  {$endif}

var
  Point, Side: TVector3;
  Margin: Single;
begin
  inherited;

  if GetExists and
    (not Params.Transparent) and
    (false in Params.ShadowVolumesReceivers) then
  begin
    {$ifdef TODO_OLD_GL_RENDERING}
    glPushMatrix;
      glMultMatrix(Params.Transform^);

      glPushAttrib(GL_ENABLE_BIT or GL_LIGHTING_BIT);
        GLEnableTexture(etNone);
        glDisable(GL_LIGHTING);
        glDisable(GL_CULL_FACE); { saved by GL_ENABLE_BIT }
        glDisable(GL_COLOR_MATERIAL); { saved by GL_ENABLE_BIT }
        glDisable(GL_ALPHA_TEST); { saved by GL_ENABLE_BIT }
        glDisable(GL_FOG); { saved by GL_ENABLE_BIT }
        glEnable(GL_DEPTH_TEST);
        RenderContext.CurrentProgram := nil;

        glColorv(Black);

        glBegin(GL_LINES);
          VisualizeRayDown(SceneManager.Camera.Position);

          Point := AvatarPositionFromCamera(SceneManager.Camera.Position);
          Side := TVector3.CrossProduct(Player.WalkNavigation.DirectionInGravityPlane, SceneManager.Camera.GravityUp);

          VisualizeRayDown(Point);

          Margin := MarginOverWater;

          VisualizeRayDown(Point + Player.WalkNavigation.DirectionInGravityPlane * Margin);
          VisualizeRayDown(Point + Player.WalkNavigation.DirectionInGravityPlane * Margin + Side * Margin);
          VisualizeRayDown(Point + Player.WalkNavigation.DirectionInGravityPlane * Margin - Side * Margin);
          VisualizeRayDown(Point + Player.WalkNavigation.DirectionInGravityPlane * Margin + Side * Margin / 2);
          VisualizeRayDown(Point + Player.WalkNavigation.DirectionInGravityPlane * Margin - Side * Margin / 2);

          VisualizeRayDown(Point - Player.WalkNavigation.DirectionInGravityPlane * Margin * 2);
          VisualizeRayDown(Point - Player.WalkNavigation.DirectionInGravityPlane * Margin * 2 + Side * Margin);
          VisualizeRayDown(Point - Player.WalkNavigation.DirectionInGravityPlane * Margin * 2 - Side * Margin);

          Margin := MarginOverWater / 2;

          VisualizeRayDown(Point + Player.WalkNavigation.DirectionInGravityPlane * Margin);
          VisualizeRayDown(Point + Player.WalkNavigation.DirectionInGravityPlane * Margin + Side * Margin);
          VisualizeRayDown(Point + Player.WalkNavigation.DirectionInGravityPlane * Margin - Side * Margin);
          VisualizeRayDown(Point + Player.WalkNavigation.DirectionInGravityPlane * Margin + Side * Margin / 2);
          VisualizeRayDown(Point + Player.WalkNavigation.DirectionInGravityPlane * Margin - Side * Margin / 2);
        glEnd();
      glPopAttrib();
    glPopMatrix();
    {$endif}
  end;
end;

end.
