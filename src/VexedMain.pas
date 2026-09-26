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
  PalmPDB
  ;

type
  TControl3DAccess = class(TControl3D);
  TForm1 = class(TForm)
    TabControl1: TTabControl;
    GorillaTab: TTabItem;
    TabItem1: TTabItem;
    Memo1: TMemo;
    Layout1: TLayout;
    GorillaViewport1: TGorillaViewport;
    GorillaCamera1: TGorillaCamera;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
  private
    { Private declarations }
    AssetsDir: String;
    Map: TArray<TArray<Integer>>;
    PDB: TPDBFile;
    Tiles: TArray<TBitmap>;
    Board: TVexedBoard;
    Theme: String;
    procedure DumpDisplayInfo;
    procedure DumpPDB(const AFile: String);
    procedure DebugAdd(const S: String); overload;
    procedure DebugAdd(const FormatString: string; const Args: array of const); overload;
  public
    { Public declarations }
  end;

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

procedure TForm1.DumpPDB(const AFile: String);
var
  I: Integer;
  V: TVexedPack;
begin
  DebugAdd('File : %s', [AFile]);
  try
    if Assigned(PDB) then
      FreeAndNil(PDB);
    PDB := DecodePDBFile(AFile);
    try
      DebugAdd('Name         : %s', [PDB.Name]);
      DebugAdd('Type/Creator : %S / %S', [PDB.DBType, PDB.Creator]);
      DebugAdd('Version      : %d', [PDB.Version]);
      DebugAdd('Created      : %s', [DateTimeToStr(PDB.CreationDate)]);
      DebugAdd('Modified     : %s', [DateTimeToStr(PDB.ModificationDate)]);
      DebugAdd('Resource DB  : %s', [BoolToStr(PDB.IsResourceDatabase, True)]);
      DebugAdd('Records      : %d', [PDB.RecordCount]);
      DebugAdd('');

      for I := 0 to PDB.RecordCount - 1 do
        DebugAdd('  #%d  UID=%d  %d bytes  deleted=%s',
          [I,
           PDB.Records[I].UniqueID,
           Length(PDB.Records[I].Data),
           BoolToStr(PDB.Records[I].IsDeleted, True)]);

        DebugAdd('');

        V := PDB.Records[0].Vexed;
        if(V <> Nil) then
          begin
            DebugAdd('Author : %s', [V.Info.Author]);
            DebugAdd('URL : %s', [V.Info.Url]);
            DebugAdd('Desc : %s', [V.Info.Description]);
            DebugAdd('');

            for I := 0 to V.LevelCount -1 do
              begin
                {$IF DEFINED(SINGLETEST)}
                if I = 32 then
                {$IFEND}
                Board := DecodeVexedBoard(V.Level[I].Board);
                DebugAdd('Title : %s',[V.Level[I].Title]);
                DebugAdd('Board : %s',[V.Level[I].Board]);
                DebugAdd('Solve : %s',[V.Level[I].Solution]);
                DebugAdd('');
              end;
          end
        else
          DebugAdd('******** Decode Error ********');
        DebugAdd('');
    finally
      // V.Free;
    end;
  except
    on E: Exception do
      DebugAdd('Error: ', [E.Message]);
  end;

end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  Theme := 'classic';

  TabControl1.ActiveTab := GorillaTab;
  // Mac and Linux paths are provisional holding places
  // Need proper paths investigating and setting for deployment
  {$IF DEFINED(MACOS)}
  AssetsDir := IncludeTrailingPathDelimiter(TPath.GetLibraryPath);
  {$ELSEIF DEFINED(LINUX)}
  AssetsDir := IncludeTrailingPathDelimiter(TPath.GetHomePath);
  {$ELSE}
  AssetsDir := '../../';
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
  if Assigned(PDB) then
    FreeAndNil(PDB);

  SetLength(Map, 0, 0);
  for I := 0 to Length(Tiles) - 1 do
    Tiles[I].Free;
  SetLength(Tiles, 0);
end;

procedure TForm1.FormResize(Sender: TObject);
begin
  Caption := Format('Width : %f, Height : %f',[GorillaViewport1.Width, GorillaViewport1.Height]);
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


procedure TForm1.FormShow(Sender: TObject);
var
  I, T: Integer;
  S : TStopwatch;
begin
  DumpDisplayInfo;
  T := 0;
  S := TStopwatch.Create;
  S.Start;
  {$IF DEFINED(SINGLETEST)}
  DumpPDB(AssetsDir + 'levels/Classic Levels.pdb');
  Inc(T);
  {$ELSE}
  // Test all packs
  for I := 0 to Length(VexedPacks) - 1 do
    begin
      DumpPDB(AssetsDir + 'levels/' + VexedPacks[I] + '.pdb');
      Inc(T);
    end;
  {$ENDIF}
  DebugAdd('');
  DebugAdd('Timing');
  DebugAdd('======');
  DebugAdd('');

  DebugAdd('Decode Time * %d = %d ms', [T, S.ElapsedMilliseconds]);
  DebugAdd('Avg. Time per Pack = %0.3f ms', [Single(S.ElapsedMilliseconds / T)]);
  S.Stop;

  SetLength(Map, 4, 3);          // 4 columns x 3 rows
  Map[0] := [0, 1, 0];
  Map[1] := [1, 1, 1];
  Map[2] := [0, -1, 0];          // -1 = empty cell, skipped
  Map[3] := [1, 0, 1];

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

  {$IF DEFINED(SINGLETEST)}
  RenderTileMap(GorillaViewport1, Board, Tiles);
  {$ELSE}
  RenderTileMap(GorillaViewport1, Map, Tiles, 128);
  {$IFEND}

end;



end.
