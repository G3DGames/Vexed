unit VexedLib;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

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

function DecodeVexedBoard(const EncodedBoard: String): TVexedBoard;

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

end.
