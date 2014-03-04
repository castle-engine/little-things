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

{$apptype GUI}

program little_things;
uses CastleWindow, CastleConfig, Game;
begin
  Config.Load;
  Application.Initialize;
  Window.OpenAndRun;
  Config.Save;
end.
