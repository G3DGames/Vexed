unit VexedLib;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.Generics.Collections,
  FMX.Types, FMX.Layouts, FMX.Objects, PalmPDB;

const
  VexedBoardMaxRow  =  7;
  VexedBoardMaxCol  =  9;

  VexedPacks : Array [0..47] of String = (
			'Children''s Pack',	'Classic Levels',	'Classic II Levels',	'Confusion Pack',	'Impossible Pack',	'Panic Pack',
			'Twister Levels',	'Variety II Pack',	'Variety Pack',			'Variety 3 Pack',	'Variety 4 Pack',	'Variety 5 Pack',
			'Variety 6 Pack',	'Variety 7 Pack',	'Variety 8 Pack',		'Variety 9 Pack',	'Variety 10 Pack',	'Variety 11 Pack',
			'Variety 12 Pack',	'Variety 13 Pack',	'Variety 14 Pack',		'Variety 15 Pack',	'Variety 16 Pack',	'Variety 17 Pack',
			'Variety 18 Pack',	'Variety 19 Pack',	'Variety 20 Pack',		'Variety 21 Pack',	'Variety 22 Pack',	'Variety 23 Pack',
			'Variety 24 Pack',	'Variety 25 Pack',	'Variety 26 Pack',		'Variety 27 Pack',	'Variety 28 Pack',	'Variety 29 Pack',
			'Variety 30 Pack',	'Variety 31 Pack',	'Variety 32 Pack',		'Variety 33 Pack',	'Variety 34 Pack',	'Variety 35 Pack',
			'Variety 36 Pack',	'Variety 37 Pack',	'Variety 38 Pack',		'Variety 39 Pack',	'Variety 40 Pack',	'Variety 41 Pack');

type
  TVexedBoard = Array [0..VexedBoardMaxRow, 0..VexedBoardMaxCol] of Integer;


  TGameLevel = class
  strict private
    FBoard: TVexedBoard;
    FEncodedBoard: String;
    FSolution: String;
    FTitle: String;
  public
    constructor Create(ALevel: TVexedLevel);
    function DecodeBoard(const EncodedBoard: String): TVexedBoard;
    property Board: TVexedBoard read FBoard;
    property EncodedBoard: String read FEncodedBoard;
    property Solution: String read FSolution;
    property Title: String read FTitle;
  end;

  TGamePack = class // A Vexed pack containing Info and multiple Levels
  strict private
    FName: String;
    FAuthor: String;
    FUrl: String;
    FDescription: String;
    FLevels: TObjectList<TGameLevel>;
    function GetLevel(Index: Integer): TGameLevel;
    function GetLevelCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function LoadFromPDB(AFile: String): Boolean;
    property Level[Index: Integer]: TGameLevel read GetLevel; default;
    property Count: Integer read GetLevelCount;
    property Name: String read FName;
    property Author: String read FAuthor;
    property Description: String read FDescription;
    property Url: String read FUrl;
  end;

  TGameCollection = class
    strict private
      FPacks: TObjectList<TGamePack>;
      function GetPack(Index: Integer): TGamePack;
      function GetPackCount: Integer;
    public
{$WARN DUPLICATE_CTOR_DTOR OFF}
      constructor Create;
      constructor CreateFromFile(const AFile: String);
      constructor CreateFromFolder(const AFolder: String);
{$WARN DUPLICATE_CTOR_DTOR ON}
      destructor Destroy; override;
      function LoadFromFile(AFile: String): Boolean;
      function LoadFromFolder(AFolder: String): Integer;
      property Pack[Index: Integer]: TGamePack read GetPack; default;
      property Count: Integer read GetPackCount;
  end;

function DecodeVexedBoard(const EncodedBoard: String): TVexedBoard;
procedure ResizeLayout(var Outer: TRectangle; var Inner: TLayout; var Resizing: Boolean; const GameAspect: TPoint);

implementation

function DecodeVexedBoard(const EncodedBoard: String): TVexedBoard;
var
  I, Row, Col, BoardLen, Idx, RunLen, Tile: Integer;
  Ch: Byte;
  EOR: Boolean;
  function PeekNext(const EncodedBoard: String; Idx, BoardLen: Integer): Byte;
  begin
    if (Idx + 2) <= BoardLen then
      Result := Ord(EncodedBoard[Idx + 2])
    else
      Result := 255;
  end;
begin
  BoardLen := Length(EncodedBoard);

  Idx := 0;
  Row := 0;
  Col := 0;
  EOR := False;

  While Idx < BoardLen do
    begin
      Ch := Ord(EncodedBoard[Idx+1]);
      // Default Run is 1 (only larger is a run of walls)
      RunLen := 1;
      // Default Tile is Wall
      Tile := 9;
      case Ch of
        // Char is a 1
        49: begin
              // Is next Char a 0 - making this 10?
              if PeekNext(EncodedBoard, Idx, BoardLen) = 48 then
                begin
                  Inc(Idx);
                  RunLen := 10;
                end;
              // There's no Else as RunLen is already 1
            end;
        // Char is 2-9 which must be a ruin of walls (and Tile is already Wall)
        50..57: RunLen := Ch - 48;
        // Char is a-h - map to Tile 1-8
        97..104: Tile := Ch - 96;
        // Char is ~ - map to Tile 0 (A blank)
        126: Tile := 0;
        // Char is / - This is the end of a row
        47: EOR := True;
      else
        Raise Exception.Create('Bad Encoded Board')
      end;

      Inc(Idx);
      if EOR then
        begin
          EOR := False;
          Inc(Row);
          Col := 0;
        end
      else
        begin
          if (Tile < 9) then
            begin
              if (Row <= VexedBoardMaxRow) and (Col <= VexedBoardMaxCol) then
                begin
                  Result[Row][Col] := Tile;
                  Inc(Col);
                end
              else
                Raise Exception.Create('Bound overflow creating board');
            end
          else
            begin
              for I := 0 to RunLen - 1 do
                begin
                  if (Row <= VexedBoardMaxRow) and (Col <= VexedBoardMaxCol) then
                    Result[Row][Col+ I] := Tile
                  else
                    Raise Exception.Create('Bound overflow creating board');
                end;
              Col := Col + RunLen;
            end;
        end;
    end;

end;

procedure ResizeLayout(var Outer: TRectangle; var Inner: TLayout; var Resizing: Boolean; const GameAspect: TPoint);
var
  PadX, PadY: Single;      // padding per side (horizontal / vertical)
  MaxW, MaxH: Single;      // hard caps on final size (0 = no cap)
  AvailW, AvailH: Single;
  TargetAspect, AvailAspect: Single;
  NewW, NewH: Single;
  PosX, PosY: Single;
begin
  // ---- Re-entrancy guard ----
  if Resizing then
    Exit;

  Resizing := True;
  try
    // ---- Configurable options ----
    PadX := 0;    // horizontal gutter on each side
    PadY := 0;    // vertical gutter on each side
    MaxW := 0;  // max final width  (set 0 for unlimited)
    MaxH := 0;  // max final height (set 0 for unlimited)

    // ---- Align must be None or FMX will overwrite our layout ----
    if Inner.Align <> TAlignLayout.None then
      Inner.Align := TAlignLayout.None;

    // ---- Usable space after padding ----
    AvailW := Outer.Width  - (PadX * 2);
    AvailH := Outer.Height - (PadY * 2);

    // ---- Guard against zero / negative / bad aspect ----
    if (AvailW <= 0) or (AvailH <= 0) or
       (GameAspect.X <= 0) or (GameAspect.Y <= 0) then
      Exit;

    TargetAspect := GameAspect.X / GameAspect.Y;
    AvailAspect  := AvailW / AvailH;

    // ---- Fit largest box of TargetAspect into the available area ----
    if AvailAspect > TargetAspect then
    begin
      // Container wider than needed -> height is the limiting factor
      NewH := AvailH;
      NewW := NewH * TargetAspect;
    end
    else
    begin
      // Container taller than needed -> width is the limiting factor
      NewW := AvailW;
      NewH := NewW / TargetAspect;
    end;

    // ---- Apply maximum size cap (preserve aspect ratio) ----
    if (MaxW > 0) and (NewW > MaxW) then
    begin
      NewW := MaxW;
      NewH := NewW / TargetAspect;
    end;
    if (MaxH > 0) and (NewH > MaxH) then
    begin
      NewH := MaxH;
      NewW := NewH * TargetAspect;
    end;

    // ---- Center within the padded area ----
    PosX := PadX + (AvailW - NewW) / 2;
    PosY := PadY + (AvailH - NewH) / 2;

    // ---- Pixel snapping (crisp edges, no sub-pixel blur) ----
    NewW := Round(NewW);
    NewH := Round(NewH);
    PosX := Round(PosX);
    PosY := Round(PosY);

    // ---- Single call: avoids intermediate reflows ----
    Inner.SetBounds(PosX, PosY, NewW, NewH);
  finally
    Resizing := False;
  end;
end;

{ TGamePack }

constructor TGamePack.Create;
begin
  inherited Create;

  FLevels := TObjectList<TGameLevel>.Create(True);
end;

destructor TGamePack.Destroy;
begin
  FLevels.Free;

  inherited;
end;

function TGamePack.GetLevel(Index: Integer): TGameLevel;
begin
  if Assigned(FLevels) then
    Result := FLevels[Index]
  else
    Result := Nil;
end;

function TGamePack.GetLevelCount: Integer;
begin
  if Assigned(FLevels) then
    Result := FLevels.Count
  else
    Result := 0;
end;

function TGamePack.LoadFromPDB(AFile: String): Boolean;
var
  LPDB: TPDBFile;
  V: TVexedPack;
  Res: Boolean;
  I: Integer;
  L: TGameLevel;
begin
  Res := False;
  if not FileExists(AFile) then
    Exit(False);

  LPDB := TPDBFile.Create;
  try
    try
      LPDB.LoadFromFile(AFile);
      if Assigned(LPDB.Records) and (LPDB.Records.Count = 1) then
        begin
          V := LPDB.Records[0].Vexed;
          if V.LevelCount > 0 then
            begin
              FName := LPDB.Name;
              FAuthor := V.Author;
              FDescription := V.Description;
              FUrl := V.Url;

              for I := 0 to V.LevelCount -1 do
                begin
                  L := TGameLevel.Create(V.Level[i]);
                  FLevels.Add(L);
                end;

              Res := True;
            end;
        end;
    except
      Res := False;
    end;
  finally
    LPDB.Free;
  end;

  Result := Res;

end;

{ TGameCollection }

constructor TGameCollection.Create;
begin
  inherited Create;

  FPacks := TObjectList<TGamePack>.Create(True);

end;

constructor TGameCollection.CreateFromFile(const AFile: String);
begin
  Create;
  LoadFromFile(AFile);
end;

constructor TGameCollection.CreateFromFolder(const AFolder: String);
begin
  Create;
  LoadFromFolder(AFolder);
end;

destructor TGameCollection.Destroy;
begin
  FPacks.Free;

  inherited;
end;

function TGameCollection.GetPack(Index: Integer): TGamePack;
begin
  if Assigned(FPacks) then
    Result := FPacks[Index]
  else
    Result := Nil;
end;

function TGameCollection.GetPackCount: Integer;
begin
  if Assigned(FPacks) then
    Result := FPacks.Count
  else
    Result := 0;
end;

function TGameCollection.LoadFromFile(AFile: String): Boolean;
var
  LPack: TGamePack;
begin
  if FileExists(AFile) then
    begin
      LPack := TGamePack.Create;
      Result := LPack.LoadFromPDB(AFile);
      if Result then
        FPacks.Add(LPack);
    end
  else
    Result := False;

end;

function TGameCollection.LoadFromFolder(AFolder: String): Integer;
var
  I: Integer;
begin
  Result := 0;
  if DirectoryExists(AFolder) then
    begin
      for I := 0 to Length(VexedPacks) - 1 do
        begin
          if LoadFromFile(IncludeTrailingPathDelimiter(AFolder) + VexedPacks[I] + '.pdb') then
            Result := Result + 1;
        end;
    end;
end;

{ TGameLevel }

constructor TGameLevel.Create(ALevel: TVexedLevel);
begin
  FTitle := ALevel.Title;
  FSolution := ALevel.Solution;
  FEncodedBoard := ALevel.Board;
  FBoard := DecodeBoard(ALevel.Board);
end;

function TGameLevel.DecodeBoard(const EncodedBoard: String): TVexedBoard;
var
  I, Row, Col, BoardLen, Idx, RunLen, Tile: Integer;
  Ch: Byte;
  EOR: Boolean;
  function PeekNext(const EncodedBoard: String; Idx, BoardLen: Integer): Byte;
  begin
    if (Idx + 2) <= BoardLen then
      Result := Ord(EncodedBoard[Idx + 2])
    else
      Result := 255;
  end;
begin
  BoardLen := Length(EncodedBoard);

  Idx := 0;
  Row := 0;
  Col := 0;
  EOR := False;

  While Idx < BoardLen do
    begin
      Ch := Ord(EncodedBoard[Idx+1]);
      // Default Run is 1 (only larger is a run of walls)
      RunLen := 1;
      // Default Tile is Wall
      Tile := 9;
      case Ch of
        // Char is a 1
        49: begin
              // Is next Char a 0 - making this 10?
              if PeekNext(EncodedBoard, Idx, BoardLen) = 48 then
                begin
                  Inc(Idx);
                  RunLen := 10;
                end;
              // There's no Else as RunLen is already 1
            end;
        // Char is 2-9 which must be a ruin of walls (and Tile is already Wall)
        50..57: RunLen := Ch - 48;
        // Char is a-h - map to Tile 1-8
        97..104: Tile := Ch - 96;
        // Char is ~ - map to Tile 0 (A blank)
        126: Tile := 0;
        // Char is / - This is the end of a row
        47: EOR := True;
      else
        Raise Exception.Create('Bad Encoded Board')
      end;

      Inc(Idx);
      if EOR then
        begin
          EOR := False;
          Inc(Row);
          Col := 0;
        end
      else
        begin
          if (Tile < 9) then
            begin
              if (Row <= VexedBoardMaxRow) and (Col <= VexedBoardMaxCol) then
                begin
                  Result[Row][Col] := Tile;
                  Inc(Col);
                end
              else
                Raise Exception.Create('Bound overflow creating board');
            end
          else
            begin
              for I := 0 to RunLen - 1 do
                begin
                  if (Row <= VexedBoardMaxRow) and (Col <= VexedBoardMaxCol) then
                    Result[Row][Col+ I] := Tile
                  else
                    Raise Exception.Create('Bound overflow creating board');
                end;
              Col := Col + RunLen;
            end;
        end;
    end;
end;

end.
