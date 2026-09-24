unit VexedMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  System.Math.Vectors, Gorilla.Control, Gorilla.Transform, Gorilla.Mesh,
  Gorilla.Model, FMX.Controls3D, Gorilla.Light, Gorilla.Viewport,
  FMX.TabControl, FMX.Layouts, Gorilla.Controller, Gorilla.Animation.Controller,
  FMX.Memo.Types, FMX.Controls.Presentation, FMX.ScrollBox, FMX.Memo,
  FMX.StdCtrls, FMX.Objects3D, Gorilla.Camera;

type
  TControl3DAccess = class(TControl3D);
  TForm1 = class(TForm)
    TabControl1: TTabControl;
    GorillaTab: TTabItem;
    TabItem1: TTabItem;
    Memo1: TMemo;
    Layout1: TLayout;
    ViewportLayout: TLayout;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    { Private declarations }
    AssetsDir: String;
    procedure DumpDisplayInfo;
    procedure SwitchModel(const AModel: String);
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

uses
  System.IOUtils,
  FMX.Platform,
{$IF DEFINED(MSWINDOWS)}
  DisplayData,
{$IFEND}
  Gorilla.DefTypes, System.Math,
  FMX.Types3D;

{$R *.fmx}

procedure TForm1.FormCreate(Sender: TObject);
begin
  TabControl1.ActiveTab := GorillaTab;

  {$IF DEFINED(MACOS)}
  AssetsDir := IncludeTrailingPathDelimiter(TPath.GetLibraryPath);
  {$ELSEIF DEFINED(LINUX)}
  AssetsDir := IncludeTrailingPathDelimiter(TPath.GetHomePath);
  {$ELSE}
  AssetsDir := '../../../';
  {$ENDIF}

  {$IF DEFINED(MSWINDOWS)}
  if DirectoryExists('images') then
    AssetsDir := String.Empty;
  {$IFEND}
end;


procedure TForm1.DumpDisplayInfo;
{$IF DEFINED(MSWINDOWS)}
var
  Displays: TPeardoxDisplays;
  Display: TDisplayInfo;
  Mode: TDisplayMode;
  I: Integer;
{$IFEND}
begin
{$IF DEFINED(MSWINDOWS)}
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

// On startup load a default Model as specified by DefaultLoadType
// The directory layout of models/Orientation follows this pattern
// to allow easy addition of new Model types
procedure TForm1.FormShow(Sender: TObject);
begin
{$IF DEFINED(MSWINDOWS)}
  DumpDisplayInfo;
{$IFEND}

end;



end.
