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

{ Game routines. }
unit GamePlay;

{$I castleconf.inc}

{ $define TOUCH_INTERFACE} // useful to test TOUCH_INTERFACE on desktops
{$ifdef ANDROID} {$define TOUCH_INTERFACE} {$endif}
{$ifdef iOS}     {$define TOUCH_INTERFACE} {$endif}

interface

uses CastleScene, CastleTransform, X3DNodes, CastlePlayer, CastleLevels,
  CastleKeysMouse, CastleUIControls;

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

uses SysUtils, CastleVectors, CastleLog, CastleWindowProgress, CastleProgress,
  CastleWindow, CastleResources, CastleTerrain, CastleCameras, CastleFilesUtils,
  Math, CastleSceneCore, CastleBoxes, CastleTimeUtils,
  CastleGL, CastleGLUtils, CastleGLShaders, Game, GamePlayer, CastleGLVersion,
  CastleUtils, X3DLoad, X3DCameraUtils, CastleRenderer,
  CastleSceneManager, CastleColors, CastleNoise,
  CastleWindowTouch, CastleControls, CastleFrustum, CastleRectangles;

type
  { TODO: Remake as TUIState descendant, use TUIState for title and game states. }
  TGameUI = class(TUIControl)
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
  CurrentPartScene: TCastleScene;

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
    Player.Camera.DirectionInGravityPlane * Player.Camera.RotationHorizontalPivot;
  Result[SceneManager.Items.GravityCoordinate] := WaterHeight; // constant height on the water
end;

function OverWater(Point: TVector3; out Height: Single): Boolean;
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
  Side := TVector3.CrossProduct(Player.Camera.DirectionInGravityPlane, SceneManager.GravityUp);
  Result :=
    { to protect forward movement }
    OverWater(Point + Player.Camera.DirectionInGravityPlane * Margin                    , Height) and
    OverWater(Point + Player.Camera.DirectionInGravityPlane * Margin + Side * Margin    , Height) and
    OverWater(Point + Player.Camera.DirectionInGravityPlane * Margin - Side * Margin    , Height) and
    OverWater(Point + Player.Camera.DirectionInGravityPlane * Margin + Side * Margin / 2, Height) and
    OverWater(Point + Player.Camera.DirectionInGravityPlane * Margin - Side * Margin / 2, Height) and

    { to protect backward movement }
    OverWater(Point - Player.Camera.DirectionInGravityPlane * Margin * 2                , Height) and
    OverWater(Point - Player.Camera.DirectionInGravityPlane * Margin * 2 + Side * Margin, Height) and
    OverWater(Point - Player.Camera.DirectionInGravityPlane * Margin * 2 - Side * Margin, Height);
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

  Scene.Attributes.WireframeEffect := weSilhouette;
  Scene.Attributes.WireframeColor := Vector3(0, 0, 0);
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
    TerrainNode: TAbstractChildNode;
    Root: TX3DRootNode;
    Appearance: TAppearanceNode;
    Texture: TImageTextureNode;
    TextureTransform: TTextureTransformNode;
    Range: TFloatRectangle;
    Material: TMaterialNode;
  const
    Size = 3;
  begin
    Appearance := TAppearanceNode.Create;

    Texture := TImageTextureNode.Create;
    Texture.SetUrl([ApplicationData('level/textures/sand.png')]);
    Appearance.Texture := Texture;

    TextureTransform := TTextureTransformNode.Create;
    TextureTransform.Scale := Vector2(10, 10);
    Appearance.TextureTransform := TextureTransform;

    Material := TMaterialNode.Create;
    Material.DiffuseColor := Vector3(1, 1, 0); { yellow }
    Appearance.Material := Material;

    Range := FloatRectangle(-Size, -Size, Size * 2, Size * 2);
    TerrainNode := Terrain.CreateNode(1 shl 6 + 1, Range, Range, Appearance);

    TerrainTransform := TTransformNode.Create;
    TerrainTransform.Translation := Vector3(
      -RealSize / 2, YShift,
      -RealSize / 2);
    TerrainTransform.Scale := Vector3(
      RealSize * 1/Size,
      RealSize * 1/Size,
      RealSize * 1/Size);
    TerrainTransform.AddChildren(TerrainNode);

    Root := TX3DRootNode.Create;
    Root.AddChildren(TerrainTransform);
    Root.AddChildren(Load3D(ApplicationData('level/' + PartName + '/part_final.x3dv')));

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
      Terrain.Seed := 1073933886; // Random(High(LongInt)); Writeln('seed is ', Terrain.Seed);
      Result := LoadTerrainPart(Terrain);
    finally FreeAndNil(Terrain) end;
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

  PaintedEffect.Enabled := PartConfig[Part].PaintedEffect;

  NewBackground := SceneManager.MainScene.RootNode.TryFindNodeByName(
    TAbstractBackgroundNode, 'Background' + PartName, false) as TAbstractBackgroundNode;
  if NewBackground <> nil then
  begin
    NewBackground.EventSet_bind.Send(true);
    WritelnLog('little_things', 'Found and bound background ' + NewBackground.X3DName);
  end;

  ConfigureScene(CurrentPartScene);
  SceneManager.Items.Add(CurrentPartScene);

  { do not use automatic MoveLimit from SceneManager.LoadLevel, it is not useful
    when we dynamically switch parts, and it doesn't make sense on pIsland part. }
  SceneManager.MoveLimit := TBox3D.Empty;

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
  Player.Navigation.OnMoveAllowed := @TGame(nil).MoveAllowed;
  SceneManager.UseGlobalLights := true;
  { Camera should not collide with 3D, only the avatar, which is done by special code in OnMoveAllowed }
  SceneManager.MainScene.Collides := false;
  WaterTransform := SceneManager.MainScene.RootNode.FindNodeByName(
    TTransformNode, 'WaterTransform', false) as TTransformNode;
  if SceneManager.MainScene.NavigationInfoStack.Top <> nil then
  begin
    VisibilityLimit := SceneManager.MainScene.NavigationInfoStack.Top.VisibilityLimit;
    WritelnLog('little_things', 'Using VisibilityLimit %f', [VisibilityLimit]);
  end;
  PaintedEffect := SceneManager.MainScene.RootNode.TryFindNodeByName(
    TScreenEffectNode, 'PaintedEffect', false) as TScreenEffectNode;

  AvatarTransform := TCastleTransform.Create(SceneManager);
  AvatarTransform.Scale := Vector3(0.3, 0.3, 0.3); // scale in code, scaling animation with cloth in Blender causes problems
  SceneManager.Items.Add(AvatarTransform);

  Avatar := TCastleScene.Create(SceneManager);
  Avatar.Load(ApplicationData('avatar/avatar.kanim'));
  Avatar.ProcessEvents := true;
  Avatar.PlayAnimation('animation', paForceLooping);
  Avatar.TimePlayingSpeed := 10;
  AvatarTransform.Add(Avatar);

  {$ifdef TOUCH_INTERFACE}
  // Do not use AutomaticTouchInterface, as we pretend we're flying for a hacky
  // 3rd-person camera, and it would cause using TouchInterface for flying.
  Window.TouchInterface := tiCtlWalkDragRotate;
  Player.EnableCameraDragging := true;
  {$else}
  Player.Camera.MouseLook := true;
  {$endif}

  DefaultMoveSpeed := Player.Navigation.MoveSpeed;

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
      [ CurrentPartScene.Attributes.SilhouetteScale,
        CurrentPartScene.Attributes.SilhouetteBias]);
  end;

var
  PolygonOffsetFactor: Single;
begin
  if EnableDebugKeys(Container) then
  begin
    if GpuATI then
      PolygonOffsetFactor := 1.0 else
      PolygonOffsetFactor := 0.1;
    if Event.IsKey(K_1) then
    begin
      CurrentPartScene.Attributes.SilhouetteScale := CurrentPartScene.Attributes.SilhouetteScale - PolygonOffsetFactor;
      ReportPolygonOffset;
    end;
    if Event.IsKey(K_2) then
    begin
      CurrentPartScene.Attributes.SilhouetteScale := CurrentPartScene.Attributes.SilhouetteScale + PolygonOffsetFactor;
      ReportPolygonOffset;
    end;
    if Event.IsKey(K_3) then
    begin
      CurrentPartScene.Attributes.SilhouetteBias := CurrentPartScene.Attributes.SilhouetteBias - PolygonOffsetFactor;
      ReportPolygonOffset;
    end;
    if Event.IsKey(K_4) then
    begin
      CurrentPartScene.Attributes.SilhouetteBias := CurrentPartScene.Attributes.SilhouetteBias + PolygonOffsetFactor;
      ReportPolygonOffset;
    end;
    if Event.IsKey(K_5) then
    begin
      SceneManager.NavigationType := ntExamine;
    end;
    if Event.IsKey(K_6) then
    begin
      if CurrentPart = High(CurrentPart) then
        LoadPart(Low(TPart)) else
        LoadPart(Succ(CurrentPart));
    end;
    if Event.IsKey(K_8) then
    begin
      RenderDebug3D := not RenderDebug3D;
      GameDebug3D.Exists := RenderDebug3D;
    end;

    if TerrainTransform <> nil then
    begin
      if Event.IsKey(K_9) then
      begin
        TerrainTransform.Scale := TerrainTransform.Scale - Vector3(0.5, 0.5, 0.5);
        WritelnLog('Terrain', TerrainTransform.Scale.ToString);
      end;
      if Event.IsKey(K_0) then
      begin
        TerrainTransform.Scale := TerrainTransform.Scale + Vector3(0.5, 0.5, 0.5);
        WritelnLog('Terrain', TerrainTransform.Scale.ToString);
      end;
      if Event.IsKey(K_P) then
      begin
        TerrainTransform.Translation := TerrainTransform.Translation - Vector3(0, 0.5, 0);
        WritelnLog('Terrain', Format('%f', [TerrainTransform.Translation[1]]));
      end;
      if Event.IsKey(K_O) then
      begin
        TerrainTransform.Translation := TerrainTransform.Translation + Vector3(0, 0.5, 0);
        WritelnLog('Terrain', Format('%f', [TerrainTransform.Translation[1]]));
      end;
    end;
  end;

  if Event.IsKey(K_F5) then
    Window.SaveScreen(FileNameAutoInc(ApplicationName + '_screen_%d.png'));
  if Event.IsKey(K_Escape) then
    Window.Close;
end;

function EnableDebugKeys(Container: TUIContainer): Boolean;
begin
  { debug keys only with Ctrl }
  Result := Container.Pressed[K_Ctrl];
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
    OldPosition := Player.Camera.Position;
    NewPosition := OldPosition + WindMove;

    if OverWaterAround(AvatarPositionFromCamera(OldPosition), MarginOverWater) and
       OverWaterAround(AvatarPositionFromCamera(NewPosition), MarginOverWater) then
      Player.Camera.Position := NewPosition;
  end;

const
  MoveSpeedChangeSpeed = 5;
  DistanceToDogToFinish = 10.0;
var
  MoveSpeedTarget: Single;
begin
  inherited;

  MoveSpeedTarget := DefaultMoveSpeed * OverWaterFactor(AvatarTransform.Translation);
  if MoveSpeedTarget > Player.Camera.MoveSpeed then
    Player.Camera.MoveSpeed := Min(Player.Camera.MoveSpeed + SecondsPassed * MoveSpeedChangeSpeed, MoveSpeedTarget) else
  if MoveSpeedTarget < Player.Camera.MoveSpeed then
    Player.Camera.MoveSpeed := Max(Player.Camera.MoveSpeed - SecondsPassed * MoveSpeedChangeSpeed, MoveSpeedTarget);

  //Writeln(Player.Camera.MoveSpeed:1:10, ' for ', AvatarTransform.Translation.ToString);

  Wind;

  { make sure CurrentPartScene knows about current camera.
    By default, only MainScene knows about it, and we want to pass it to CurrentPartScene
    to use CurrentPartScene.DistanceCulling. }
  CurrentPartScene.CameraChanged(SceneManager.Camera);

  if (DogTransform <> nil) and
     (PointsDistanceSqr(DogTransform.Translation, Player.Camera.Position) <
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
    OrientationFromDirectionUp(Player.Camera.DirectionInGravityPlane, SceneManager.GravityUp);

  AvatarTransform.Translation := AvatarPositionFromCamera(Player.Camera.Position);
end;

{ TGameDebug3D --------------------------------------------------------------- }

function TGameDebug3D.LocalBoundingBox: TBox3D;
begin
  Result := SceneManager.MainScene.BoundingBox;
end;

procedure TGameDebug3D.LocalRender(const Params: TRenderParams);

  {$ifndef OpenGLES} // TODO-es
  procedure VisualizeRayDown(Point: TVector3);
  begin
    Point[SceneManager.Items.GravityCoordinate] := -HeightOverAvatar;
//    Writeln(Point.ToString);
    glVertexv(Point);

    Point[SceneManager.Items.GravityCoordinate] := +HeightOverAvatar;
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
    {$ifndef OpenGLES} // TODO-es
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
        TGLSLProgram.Current := nil;

        glColorv(Black);

        glBegin(GL_LINES);
          VisualizeRayDown(Player.Camera.Position);

          Point := AvatarPositionFromCamera(Player.Camera.Position);
          Side := TVector3.CrossProduct(Player.Camera.DirectionInGravityPlane, SceneManager.GravityUp);

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
    glPopMatrix();
    {$endif}
  end;
end;

end.
