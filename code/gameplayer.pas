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

{ Player, common for game and title screen. }
unit GamePlayer;

interface

uses CastleLevels, CastlePlayer;

var
  SceneManager: TGameSceneManager;
  Player: TPlayer; //< same thing as Window.SceneManager.Player
  TitleScreen: boolean; //< current game state

procedure StartPlayer;

implementation

procedure StartPlayer;
begin
  Player := TPlayer.Create(SceneManager);
  Player.Navigation.RotationHorizontalPivot := 5;
//  Player.Flying := true; // no gravity
  SceneManager.Player := Player;
end;

end.
