unit TileMapRenderer;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Math.Vectors,
  FMX.Types, FMX.Types3D, FMX.Layers3D, FMX.Controls3D, FMX.Graphics;

/// <summary>
///   Builds a grid of TImage3D tiles inside AParent (typically a TViewport3D)
///   based on Map values that index into Tiles.
///
///   Note: TLayer3D itself has no Bitmap property -- it's a container for
///   hosting ordinary 2D controls on a surface in 3D space. TImage3D is the
///   sibling class in FMX.Layers3D that actually paints a bitmap onto a 3D
///   quad (it implements IBitmapObject and publishes Bitmap/Width/Height),
///   so it's the right building block for a tile grid like this.
/// </summary>
/// <param name="AParent">
///   The 3D container that will own/parent the generated TImage3D tiles
///   (e.g. a TViewport3D on your form).
/// </param>
/// <param name="Map">
///   X by Y dynamic array of integers. Map[X][Y] is the index into Tiles
///   used for that grid cell. Use -1 (or any out-of-range value) for "no tile".
/// </param>
/// <param name="Tiles">
///   Dynamic array of equally-sized square TBitmap tile images, indexed by
///   the values stored in Map.
/// </param>
/// <param name="TileSize">
///   Width/Height (in 3D units) each tile is drawn at, and the spacing step
///   between grid cells.
/// </param>
procedure RenderTileMap(AParent: TFmxObject; const Map: TArray<TArray<Integer>>;
  const Tiles: TArray<TBitmap>; TileSize: Single = 64);

implementation

procedure RenderTileMap(AParent: TFmxObject; const Map: TArray<TArray<Integer>>;
  const Tiles: TArray<TBitmap>; TileSize: Single = 64);
var
  X, Y: Integer;
  MapWidth, MapHeight: Integer;
  TileIndex: Integer;
  Layer: TImage3D;
  i: Integer;
begin
  if AParent = nil then
    raise EArgumentException.Create('AParent must not be nil');

  MapWidth := Length(Map);
  if MapWidth = 0 then
    Exit;
  MapHeight := Length(Map[0]);
  if MapHeight = 0 then
    Exit;

  // Clear out any tiles from a previous render, so this can be called
  // repeatedly (e.g. when switching levels) without leaking layers.
  for i := AParent.ChildrenCount - 1 downto 0 do
    if AParent.Children[i] is TImage3D then
      AParent.Children[i].Free;

  for X := 0 to MapWidth - 1 do
  begin
    if Length(Map[X]) <> MapHeight then
      raise Exception.CreateFmt('Map is not rectangular: column %d has %d rows, expected %d',
        [X, Length(Map[X]), MapHeight]);

    for Y := 0 to MapHeight - 1 do
    begin
      TileIndex := Map[X][Y];

      // Skip empty / invalid cells rather than raising, so sparse maps work.
      if (TileIndex < 0) or (TileIndex > High(Tiles)) or (Tiles[TileIndex] = nil) then
        Continue;

      Layer := TImage3D.Create(AParent);
      Layer.Parent := AParent;
      Layer.Width  := TileSize;
      Layer.Height := TileSize;

      // Copy the tile bitmap into the layer's own Bitmap.
      Layer.Bitmap.Assign(Tiles[TileIndex]);

      // Lay the grid out on the XY plane, Z = 0.
      // FMX 3D's Y axis points downward on screen by default, which matches
      // typical row-major map layouts (row 0 at the top).
      Layer.Position.Point := TPoint3D.Create(X * TileSize, Y * TileSize, 0);

      Layer.HitTest := False; // tiles are just visuals; flip on if you need picking
    end;
  end;
end;

end.
