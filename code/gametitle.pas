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

{ Title screen, actually a normal 3D level. }
unit GameTitle;

interface

uses CastleLevels, CastlePlayer, CastleKeysMouse, CastleUIControls;

procedure StartTitleScreen;

procedure TitlePress(Container: TUIContainer; const Event: TInputPressRelease);

implementation

uses GamePlayer, GamePlay;

procedure StartTitleScreen;
begin
  TitleScreen := true;

  SceneManager.LoadLevel('title');
  Player.Blocked := true;
end;

procedure TitlePress(Container: TUIContainer; const Event: TInputPressRelease);
begin
  if Event.IsMouseButton(buttonLeft) or
     Event.IsKey(keyEnter) or
     Event.IsKey(keyEscape) then
    StartGame;
end;

end.
