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

{$apptype GUI}

{ "Little Things" standalone game binary. }
program little_things;

{$ifdef MSWINDOWS} {$R automatic-windows-resources.res} {$endif MSWINDOWS}

uses CastleWindow, CastleConfig, Game, CastleParameters, CastleLog, CastleUtils,
  CastleSoundEngine;

const
  Options: array [0..0] of TOption =
  (
    (Short:  #0; Long: 'debug-log'; Argument: oaNone)
  );

procedure OptionProc(OptionNum: Integer; HasArgument: boolean;
  const Argument: string; const SeparateArgs: TSeparateArgs; Data: Pointer);
begin
  case OptionNum of
    0: InitializeLog;
    else raise EInternalError.Create('OptionProc');
  end;
end;

begin
  UserConfig.Load;
  SoundEngine.LoadFromConfig(UserConfig); // before SoundEngine.ParseParameters

  Window.FullScreen := true;
  Window.ParseParameters;
  SoundEngine.ParseParameters;
  Parameters.Parse(Options, @OptionProc, nil);

  Window.OpenAndRun;
  UserConfig.Save;
end.
