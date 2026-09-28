unit VexedMain;

interface

{$DEFINE SINGLETEST}


uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  System.Math.Vectors, Gorilla.Control, Gorilla.Transform, Gorilla.Mesh,
  Gorilla.Model, FMX.Controls3D, Gorilla.Light, Gorilla.Viewport,
  FMX.TabControl, FMX.Layouts, Gorilla.Controller, Gorilla.Animation.Controller,
  FMX.Memo.Types, FMX.Controls.Presentation, FMX.ScrollBox, FMX.Memo,
  FMX.StdCtrls, FMX.Objects3D, Gorilla.Camera, FMX.Viewport3D,
  VexedLib,
  PalmPDB, FMX.Menus, FMX.Objects, FMX.Layers3D
  ;

type
  TControl3DAccess = class(TControl3D);
  TForm1 = class(TForm)
    TabControl1: TTabControl;
    GorillaTab: TTabItem;
    TabItem1: TTabItem;
    Memo1: TMemo;
    ScoreLayout: TLayout;
    MainMenu1: TMainMenu;
    MenuItem1: TMenuItem;
    GameLayout: TRectangle;
    GameBox: TLayout;
    GorillaCamera1: TGorillaCamera;
    GorillaViewport1: TGorillaViewport;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure GameBoxResize(Sender: TObject);
  private
    { Private declarations }
    FResizing: Boolean;
    AssetsDir: String;
    Map: TArray<TArray<Integer>>;
    Puzzles: TGameCollection;
    Tiles: TArray<TBitmap>;
    Board: TVexedBoard;
    Theme: String;
    GameAspect: TPoint;
    procedure DumpDisplayInfo;
    procedure DumpCollection;
    procedure DebugAdd(const S: String); overload;
    procedure DebugAdd(const FormatString: string; const Args: array of const); overload;
  public
    { Public declarations }
  end;

const
  GameWidth: Integer = 10;
  GameHeight: Integer = 8;

var
  Form1: TForm1;

implementation

uses
  System.IOUtils,
  FMX.Platform,
{$IF DEFINED(DMSWINDOWS)}
  DisplayData,
{$IFEND}
  Gorilla.DefTypes, System.Math,
  TileMapRenderer,
  System.Diagnostics,
  FMX.Types3D;

{$R *.fmx}

procedure TForm1.FormCreate(Sender: TObject);
begin
  Theme := 'classic';
  GameAspect := Point(GameWidth, GameHeight);
  TabControl1.ActiveTab := GorillaTab;
  // Mac and Linux paths are provisional holding places
  // Need proper paths investigating and setting for deployment
  {$IF DEFINED(MACOS)}
  AssetsDir := IncludeTrailingPathDelimiter(TPath.GetLibraryPath);
  {$ELSEIF DEFINED(LINUX)}
  AssetsDir := IncludeTrailingPathDelimiter(TPath.GetHomePath);
  {$ELSE}
  AssetsDir := '..' + PathDelim + '..'  + PathDelim;
  {$ENDIF}

  {$IF DEFINED(MSWINDOWS)}
  if DirectoryExists('images') then
    AssetsDir := String.Empty;
  {$IFEND}

  GorillaCamera1.Parent := GorillaViewport1;
  GorillaCamera1.ProjectionMode := cpOrthographic;
  GorillaCamera1.OrthoHeight := 1024;
  GorillaCamera1.Position.X := 640 - 64;
  GorillaCamera1.Position.Y := 512 - 64;
  GorillaViewport1.Camera := GorillaCamera1;
  GorillaViewport1.UsingDesignCamera := False;

end;


procedure TForm1.FormDestroy(Sender: TObject);
var
  I: Integer;
begin
  if Assigned(Puzzles) then
    Puzzles.Free;

  SetLength(Map, 0, 0);
  for I := 0 to Length(Tiles) - 1 do
    Tiles[I].Free;
  SetLength(Tiles, 0);
end;

procedure TForm1.FormResize(Sender: TObject);
begin
  Caption := Format('Width : %f, Height : %f',[GorillaViewport1.Width, GorillaViewport1.Height]);
  GameBoxResize(Nil);
end;

procedure TForm1.GameBoxResize(Sender: TObject);
begin
  ResizeLayout(GameLayout, GameBox, FResizing, GameAspect);
end;

procedure TForm1.FormShow(Sender: TObject);
var
  T: Integer;
  S : TStopwatch;
  var L: Integer;
begin
  DumpDisplayInfo;

  T := 0;
  S := TStopwatch.Create;
  S.Start;

  {$IF DEFINED(SINGLETEST)}
  Puzzles := TGameCollection.CreateFromFile(AssetsDir + 'levels/Classic Levels.pdb');
  T := 1;
  L := random(Puzzles.Pack[0].Count);
  Board := Puzzles.Pack[0].Level[L].Board;
  {$ELSE}
  Puzzles := TGameCollection.CreateFromFolder(AssetsDir + 'levels');
  T := Puzzles.Count;
  var P: Integer := random(T);
  L := random(Puzzles.Pack[P].Count);
  Board := Puzzles.Pack[P].Level[L].Board;
  {$IFEND}

  DebugAdd('');
  DebugAdd('Timing');
  DebugAdd('======');
  DebugAdd('');

  DebugAdd('Decode Time * %d = %d ms', [T, S.ElapsedMilliseconds]);
  DebugAdd('Avg. Time per Pack = %0.3f ms', [Single(S.ElapsedMilliseconds / T)]);
  S.Stop;

  DumpCollection;

  SetLength(Tiles, 10);
  Tiles[0] := TBitmap.CreateFromFile(AssetsDir + 'images/blank.png');
  Tiles[1] := TBitmap.CreateFromFile(AssetsDir + 'images/' + Theme + '/tile1.png');
  Tiles[2] := TBitmap.CreateFromFile(AssetsDir + 'images/' + Theme + '/tile2.png');
  Tiles[3] := TBitmap.CreateFromFile(AssetsDir + 'images/' + Theme + '/tile3.png');
  Tiles[4] := TBitmap.CreateFromFile(AssetsDir + 'images/' + Theme + '/tile4.png');
  Tiles[5] := TBitmap.CreateFromFile(AssetsDir + 'images/' + Theme + '/tile5.png');
  Tiles[6] := TBitmap.CreateFromFile(AssetsDir + 'images/' + Theme + '/tile6.png');
  Tiles[7] := TBitmap.CreateFromFile(AssetsDir + 'images/' + Theme + '/tile7.png');
  Tiles[8] := TBitmap.CreateFromFile(AssetsDir + 'images/' + Theme + '/tile8.png');
  Tiles[9] := TBitmap.CreateFromFile(AssetsDir + 'images/wall.png');

  RenderTileMap(GorillaViewport1, Board, Tiles);

end;

procedure TForm1.DumpCollection;
var
  I: Integer;
  P: TGamePack;
  L: Integer;
  V: TGameLevel;
begin
      for I := 0 to Puzzles.Count - 1 do
        begin
          P := Puzzles.Pack[I];
          DebugAdd('');
          DebugAdd('Pack   : %d', [I]);
          DebugAdd('Name   : %s', [P.Name]);
          DebugAdd('Author : %s', [P.Author]);
          DebugAdd('URL    : %s', [P.Url]);
          DebugAdd('Desc   : %s', [P.Description]);
          DebugAdd('');

          for L := 0 to  P.Count -1 do
            begin
              V := P.Level[L];
              DebugAdd('Level : %d',[L]);
              DebugAdd('Title : %s',[V.Title]);
              DebugAdd('Board : %s',[V.EncodedBoard]);
              DebugAdd('Solve : %s',[V.Solution]);
              DebugAdd('');
            end;
        end;

end;

procedure TForm1.DebugAdd(const S: String);
begin
  Memo1.Lines.Add(S);
end;

procedure TForm1.DebugAdd(const FormatString: string; const Args: array of const);
begin
  Memo1.Lines.Add(Format(FormatString, Args));
end;

procedure TForm1.DumpDisplayInfo;
{$IF DEFINED(DMSWINDOWS)}
var
  Displays: TPeardoxDisplays;
  Display: TDisplayInfo;
  Mode: TDisplayMode;
  I: Integer;
{$IFEND}
begin
{$IF DEFINED(DMSWINDOWS)}
  Memo1.Lines.Clear;

  Displays := TPeardoxDisplays.Create;
  try
    for I := 0 to Displays.Count - 1 do
    begin
      Display := Displays[I];

      Memo1.Lines.Add(Format('Device: %s', [Display.DeviceName]));
      Memo1.Lines.Add(Format('  FriendlyName: %s', [Display.FriendlyName]));
      if Display.WidthMm > 0 then
        Memo1.Lines.Add(Format('  Size: %d x %d mm  (%.1f")',
          [Display.WidthMm, Display.HeightMm, Display.DiagonalInches]))
      else
        Memo1.Lines.Add('  Size: unknown');

      Memo1.Lines.Add(Format('  Primary: %s', [BoolToStr(Display.IsPrimary, True)]));
      Memo1.Lines.Add(Format('  Bounds: (%d, %d) - (%d, %d)',
        [Display.MonitorRect.Left, Display.MonitorRect.Top,
         Display.MonitorRect.Right, Display.MonitorRect.Bottom]));
      Memo1.Lines.Add(Format('  Work Area: (%d, %d) - (%d, %d)',
        [Display.WorkRect.Left, Display.WorkRect.Top,
         Display.WorkRect.Right, Display.WorkRect.Bottom]));
       Memo1.Lines.Add('  Current: ' + Display.CurrentMode.ToString);
{$IF DEFINED(SHOWMODES)}
      Memo1.Lines.Add('  Available modes:');
      for Mode in Display.AvailableModes do
        Memo1.Lines.Add('    ' + Mode.ToString);
{$IFEND}
      Memo1.Lines.Add('');
    end;
 finally
    Displays.Free; // frees the list
  end;
{$IFEND}
end;

end.
