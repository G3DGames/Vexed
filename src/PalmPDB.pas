unit PalmPDB;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  EByteBufferError = class(Exception);
  EVexedError = class(Exception);

  TByteBuffer = class
  private
    FBuffer: TBytes;
    FPosition: Integer; // read/write cursor
    FSize: Integer;     // logical length of valid data
    procedure EnsureCapacity(ARequired: Integer);
    procedure CheckReadable(ACount: Integer);
    function ReadByteAt(APos: Integer): Byte;
    function ReadWordAt(APos: Integer): Word;
    function ReadStringAt(APos: Integer; out ANextPos: Integer): string;
    function ReadFixedStringAt(APos, ASlotSize: Integer): string;
  public
    constructor Create; overload;
    constructor Create(const AData: TBytes); overload;

    // --- Reading (advances cursor) ---
    function ReadByte: Byte;
    function ReadWord: Word;
    function ReadString: string;

    // --- Peeking (does not advance cursor) ---
    function PeekWord: Word;
    function PeekString: string;

    // --- Writing (extends buffer, advances cursor) ---
    procedure WriteWord(AValue: Word);
    procedure WriteString(const AValue: string);

    // --- Overwrite-in-place (does not extend FSize) ---
    procedure OverwriteWord(AValue: Word);
    procedure OverwriteString(const AValue: string);

    // --- Navigation / state ---
    procedure Seek(APosition: Integer);
    function Eof: Boolean;

    // --- Fixed-width string slots ---
    function ReadFixedString(ASlotSize: Integer): string;
    function PeekFixedString(ASlotSize: Integer): string;
    procedure WriteFixedString(const AValue: string; ASlotSize: Integer);
    procedure OverwriteFixedString(const AValue: string; ASlotSize: Integer);

    // --- Access ---
    function ToBytes: TBytes;

    property Position: Integer read FPosition;
    property Size: Integer read FSize;
  end;

  TVexedInfo = class // Marked by General, followed by KV stream
  strict private
    FAuthor: String;
    FUrl: String;
    FDescription: String;
  public
    procedure SetAuthor(const AValue: String);
    procedure SetUrl(const AValue: String);
    procedure SetDescription(const AValue: String);
    property Author: String read FAuthor;
    property Url: String read FUrl;
    property Description: String read FDescription;
  end;

  TVexedLevel = class // Marked by Level, followed by KV stream
  strict private
    FBoard: String;
    FSolution: String;
    FTitle: String;
  public
    procedure SetBoard(const AValue: String);
    procedure SetSolution(const AValue: String);
    procedure SetTitle(const AValue: String);
    property Board: String read FBoard;
    property Solution: String read FSolution;
    property Title: String read FTitle;
  end;

  TVexedPack = class // A Vexed pack containing Info and multiple levels
  strict private
    FInfo: TVexedInfo;
    FLevels: TObjectList<TVexedLevel>;
    function GetLevel(Index: Integer): TVexedLevel;
    function GetLevelCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddInfo(AValue: TVexedInfo);
    procedure AddLevel(ALevel: TVexedLevel);
    property Level[Index: Integer]: TVexedLevel read GetLevel; default;
    property LevelCount: Integer read GetLevelCount;
    property Info: TVexedInfo read FInfo;
  end;

  TPDBRecord = class
  strict private
    FVexed: TVexedPack;
  public
    Attributes: Byte;      // Record attribute flags (high nibble) + category (low)
    UniqueID: Cardinal;    // 3-byte unique record ID (0..$FFFFFF)
    Data: TBytes;          // Raw record payload
    constructor Create;
    destructor Destroy; override;
    function IsDeleted: Boolean;
    function IsDirty: Boolean;
    function IsBusy: Boolean;
    function IsSecret: Boolean;
    procedure DecodeVexedData;
    property Vexed: TVexedPack read FVexed write FVexed;
  end;

  TPDBFile = class
  private
    FRecords: TObjectList<TPDBRecord>;
    function GetRecord(Index: Integer): TPDBRecord;
    function GetRecordCount: Integer;
  public
    { Header fields }
    Name: string;
    Attributes: Word;
    Version: Word;
    CreationDate: TDateTime;
    ModificationDate: TDateTime;
    LastBackupDate: TDateTime;
    ModificationNumber: Cardinal;
    appInfoID: Cardinal;           // offset to start of Application Info (if present) or null
    sortInfoID: Cardinal;          // offset to start of Sort Info (if present) or null
    DBType: string;                // 4-char type
    Creator: string;               // 4-char creator ID
    UniqueIDSeed: Cardinal;        // used internally to identify record

    AppInfoBlock: TBytes;
    SortInfoBlock: TBytes;

    constructor Create;
    destructor Destroy; override;

    { Loading }
    procedure LoadFromStream(Stream: TStream);
    procedure LoadFromFile(const AFileName: string);

    { Saving — recomputes all offsets }
    procedure SaveToStream(Stream: TStream);
    procedure SaveToFile(const AFileName: string);

    function AddRecord: TPDBRecord;

    property Records: TObjectList<TPDBRecord> read FRecords;
    property Record_[Index: Integer]: TPDBRecord read GetRecord; default;
    property RecordCount: Integer read GetRecordCount;

    function IsResourceDatabase: Boolean;
  end;

{ Convenience: decode a PDB file from disk in one call. }
function DecodePDBFile(const AFileName: string): TPDBFile;

implementation

const
  dmHdrAttrResDB = $0001;

  PDB_HEADER_SIZE   = 78; // fixed header up to record-list header
  RECLIST_HDR_SIZE  = 6;  // nextRecordListID(4) + numRecords(2)
  RECLIST_ENTRY_SIZE = 8; // offset(4) + attr(1) + uniqueID(3)
  GROW_MIN = 64;

{ TByteBuffer }

constructor TByteBuffer.Create;
begin
  inherited Create;
  SetLength(FBuffer, 0);
  FPosition := 0;
  FSize := 0;
end;

constructor TByteBuffer.Create(const AData: TBytes);
begin
  inherited Create;
  FBuffer := Copy(AData, 0, Length(AData));
  FPosition := 0;
  FSize := Length(FBuffer);
end;

procedure TByteBuffer.EnsureCapacity(ARequired: Integer);
var
  NewCap: Integer;
begin
  if ARequired <= Length(FBuffer) then
    Exit;

  NewCap := Length(FBuffer);
  if NewCap < GROW_MIN then
    NewCap := GROW_MIN;
  while NewCap < ARequired do
    NewCap := NewCap * 2;

  SetLength(FBuffer, NewCap);
end;

procedure TByteBuffer.CheckReadable(ACount: Integer);
begin
  if ACount < 0 then
    raise EByteBufferError.Create('Negative read count');
  if FPosition + ACount > FSize then
    raise EByteBufferError.CreateFmt(
      'Read past end of buffer (pos=%d, need=%d, size=%d)',
      [FPosition, ACount, FSize]);
end;

// --- Positional primitives (shared by read & peek) ---

function TByteBuffer.ReadByteAt(APos: Integer): Byte;
begin
  if (APos < 0) or (APos + SizeOf(Byte) > FSize) then
    raise EByteBufferError.CreateFmt(
      'Read past end of buffer (pos=%d, need=%d, size=%d)',
      [APos, SizeOf(Byte), FSize]);
  // Big-endian: high byte first.
  Result := Byte(FBuffer[APos]);
end;

function TByteBuffer.ReadWordAt(APos: Integer): Word;
begin
  if (APos < 0) or (APos + SizeOf(Word) > FSize) then
    raise EByteBufferError.CreateFmt(
      'Read past end of buffer (pos=%d, need=%d, size=%d)',
      [APos, SizeOf(Word), FSize]);
  // Big-endian: high byte first.
  Result := (Word(FBuffer[APos]) shl 8) or
            Word(FBuffer[APos + 1]);
end;

function TByteBuffer.ReadStringAt(APos: Integer; out ANextPos: Integer): string;
var
  StartPos, Len: Integer;
  Raw: TBytes;
begin
  if (APos < 0) or (APos > FSize) then
    raise EByteBufferError.CreateFmt(
      'String start out of range (pos=%d, size=%d)', [APos, FSize]);

  StartPos := APos;
  while (APos < FSize) and (FBuffer[APos] <> 0) do
    Inc(APos);

  if APos >= FSize then
    raise EByteBufferError.Create(
      'Unterminated string: null terminator not found before end of buffer');

  Len := APos - StartPos;
  SetLength(Raw, Len);
  if Len > 0 then
    Move(FBuffer[StartPos], Raw[0], Len);

  ANextPos := APos + 1; // consume terminator
  Result := TEncoding.ANSI.GetString(Raw);
end;

// --- Reading (advances cursor) ---

function TByteBuffer.ReadByte: Byte;
begin
  Result := ReadByteAt(FPosition);
  Inc(FPosition, SizeOf(Byte));
end;

function TByteBuffer.ReadWord: Word;
begin
  Result := ReadWordAt(FPosition);
  Inc(FPosition, SizeOf(Word));
end;

function TByteBuffer.ReadString: string;
var
  NextPos: Integer;
begin
  Result := ReadStringAt(FPosition, NextPos);
  FPosition := NextPos;
end;

// --- Peeking (does not advance cursor) ---

function TByteBuffer.PeekWord: Word;
begin
  Result := ReadWordAt(FPosition);
end;

function TByteBuffer.PeekString: string;
var
  NextPos: Integer;
begin
  Result := ReadStringAt(FPosition, NextPos);
end;

// --- Writing (extends buffer, advances cursor) ---

procedure TByteBuffer.WriteWord(AValue: Word);
begin
  EnsureCapacity(FPosition + SizeOf(Word));
  // Big-endian: high byte first.
  FBuffer[FPosition]     := Byte((AValue shr 8) and $FF);
  FBuffer[FPosition + 1] := Byte(AValue and $FF);
  Inc(FPosition, SizeOf(Word));
  if FPosition > FSize then
    FSize := FPosition;
end;

procedure TByteBuffer.WriteString(const AValue: string);
var
  Raw: TBytes;
  Len: Integer;
begin
  Raw := TEncoding.ANSI.GetBytes(AValue);
  Len := Length(Raw);

  EnsureCapacity(FPosition + Len + 1);
  if Len > 0 then
    Move(Raw[0], FBuffer[FPosition], Len);
  Inc(FPosition, Len);

  FBuffer[FPosition] := 0; // C-style null terminator
  Inc(FPosition);

  if FPosition > FSize then
    FSize := FPosition;
end;

// --- Overwrite-in-place (does not extend FSize) ---

procedure TByteBuffer.OverwriteWord(AValue: Word);
begin
  if FPosition + SizeOf(Word) > FSize then
    raise EByteBufferError.CreateFmt(
      'Overwrite past end of valid data (pos=%d, need=%d, size=%d)',
      [FPosition, SizeOf(Word), FSize]);

  FBuffer[FPosition]     := Byte((AValue shr 8) and $FF);
  FBuffer[FPosition + 1] := Byte(AValue and $FF);
  Inc(FPosition, SizeOf(Word));
end;

procedure TByteBuffer.OverwriteString(const AValue: string);
var
  Raw: TBytes;
  Len, Total: Integer;
begin
  Raw := TEncoding.ANSI.GetBytes(AValue);
  Len := Length(Raw);
  Total := Len + 1; // include null terminator

  if FPosition + Total > FSize then
    raise EByteBufferError.CreateFmt(
      'Overwrite past end of valid data (pos=%d, need=%d, size=%d)',
      [FPosition, Total, FSize]);

  if Len > 0 then
    Move(Raw[0], FBuffer[FPosition], Len);
  Inc(FPosition, Len);

  FBuffer[FPosition] := 0;
  Inc(FPosition);
end;

// --- Navigation / state ---

procedure TByteBuffer.Seek(APosition: Integer);
begin
  if (APosition < 0) or (APosition > FSize) then
    raise EByteBufferError.CreateFmt(
      'Seek out of range (pos=%d, size=%d)', [APosition, FSize]);
  FPosition := APosition;
end;

function TByteBuffer.Eof: Boolean;
begin
  Result := FPosition >= FSize;
end;

// --- Access ---

function TByteBuffer.ToBytes: TBytes;
begin
  Result := Copy(FBuffer, 0, FSize);
end;

// --- Fixed-width string slots ---

function TByteBuffer.ReadFixedStringAt(APos, ASlotSize: Integer): string;
var
  Len: Integer;
  Raw: TBytes;
begin
  if ASlotSize < 0 then
    raise EByteBufferError.Create('Negative slot size');
  if (APos < 0) or (APos + ASlotSize > FSize) then
    raise EByteBufferError.CreateFmt(
      'Read past end of buffer (pos=%d, need=%d, size=%d)',
      [APos, ASlotSize, FSize]);

  // The slot is fixed width; the logical string ends at the first null
  // (or at the slot boundary if there is no null within the slot).
  Len := 0;
  while (Len < ASlotSize) and (FBuffer[APos + Len] <> 0) do
    Inc(Len);

  SetLength(Raw, Len);
  if Len > 0 then
    Move(FBuffer[APos], Raw[0], Len);

  Result := TEncoding.ANSI.GetString(Raw);
end;

function TByteBuffer.ReadFixedString(ASlotSize: Integer): string;
begin
  Result := ReadFixedStringAt(FPosition, ASlotSize);
  Inc(FPosition, ASlotSize); // always consume the whole slot
end;

function TByteBuffer.PeekFixedString(ASlotSize: Integer): string;
begin
  Result := ReadFixedStringAt(FPosition, ASlotSize);
end;

procedure TByteBuffer.WriteFixedString(const AValue: string; ASlotSize: Integer);
var
  Raw: TBytes;
  Len: Integer;
begin
  if ASlotSize < 1 then
    raise EByteBufferError.Create(
      'Slot size must be at least 1 (room for a null terminator)');

  Raw := TEncoding.ANSI.GetBytes(AValue);
  Len := Length(Raw);

  // Must fit the string AND at least one null terminator inside the slot.
  if Len >= ASlotSize then
    raise EByteBufferError.CreateFmt(
      'String too long for slot (bytes=%d, slot=%d, need <=%d)',
      [Len, ASlotSize, ASlotSize - 1]);

  EnsureCapacity(FPosition + ASlotSize);

  // Zero-fill the whole slot first so no stale bytes remain.
  FillChar(FBuffer[FPosition], ASlotSize, 0);
  if Len > 0 then
    Move(Raw[0], FBuffer[FPosition], Len);

  Inc(FPosition, ASlotSize);
  if FPosition > FSize then
    FSize := FPosition;
end;

procedure TByteBuffer.OverwriteFixedString(const AValue: string;
  ASlotSize: Integer);
var
  Raw: TBytes;
  Len: Integer;
begin
  if ASlotSize < 1 then
    raise EByteBufferError.Create(
      'Slot size must be at least 1 (room for a null terminator)');

  Raw := TEncoding.ANSI.GetBytes(AValue);
  Len := Length(Raw);

  if Len >= ASlotSize then
    raise EByteBufferError.CreateFmt(
      'String too long for slot (bytes=%d, slot=%d, need <=%d)',
      [Len, ASlotSize, ASlotSize - 1]);

  // Overwrite must stay within existing valid data; never extend FSize.
  if FPosition + ASlotSize > FSize then
    raise EByteBufferError.CreateFmt(
      'Overwrite past end of valid data (pos=%d, need=%d, size=%d)',
      [FPosition, ASlotSize, FSize]);

  // Zero-fill the entire slot to clear any previous, longer contents.
  FillChar(FBuffer[FPosition], ASlotSize, 0);
  if Len > 0 then
    Move(Raw[0], FBuffer[FPosition], Len);

  Inc(FPosition, ASlotSize);
end;

{ ============================================================
  Endianness helpers.

  PDB files are ALWAYS big-endian. We convert to/from the host's
  native byte order. On the little-endian targets Delphi actually
  supports these swap; the conditional keeps the code correct even
  if compiled for a hypothetical big-endian target.
  ============================================================ }

{$IFDEF BIGENDIAN}
function ToBE16(V: Word): Word; inline; begin Result := V; end;
function ToBE32(V: Cardinal): Cardinal; inline; begin Result := V; end;
function FromBE16(V: Word): Word; inline; begin Result := V; end;
function FromBE32(V: Cardinal): Cardinal; inline; begin Result := V; end;
{$ELSE}

{$R-}  // disable range checking for the swap routines
{$Q-}  // disable overflow checking

function SwapW(V: Word): Word; inline;
begin
  Result := ((V and $00FF) shl 8) or ((V and $FF00) shr 8);
end;

function SwapD(V: Cardinal): Cardinal; inline;
begin
  Result := ((V and $000000FF) shl 24) or
            ((V and $0000FF00) shl 8)  or
            ((V and $00FF0000) shr 8)  or
            ((V and $FF000000) shr 24);
end;

{$IFDEF RANGECHECKS_ON}{$R+}{$ENDIF}   // (optional) restore if you track it
{$IFDEF OVERFLOWCHECKS_ON}{$Q+}{$ENDIF}

function ToBE16(V: Word): Word; inline;         begin Result := SwapW(V); end;
function ToBE32(V: Cardinal): Cardinal; inline; begin Result := SwapD(V); end;
function FromBE16(V: Word): Word; inline;       begin Result := SwapW(V); end;
function FromBE32(V: Cardinal): Cardinal; inline; begin Result := SwapD(V); end;
{$ENDIF}

{ ---- Big-endian stream primitives ---- }

function ReadU8(Stream: TStream): Byte;
begin
  Stream.ReadBuffer(Result, 1);
end;

function ReadU16(Stream: TStream): Word;
var Raw: Word;
begin
  Stream.ReadBuffer(Raw, 2);
  Result := FromBE16(Raw);
end;

function ReadU32(Stream: TStream): Cardinal;
var Raw: Cardinal;
begin
  Stream.ReadBuffer(Raw, 4);
  Result := FromBE32(Raw);
end;

procedure WriteU8(Stream: TStream; V: Byte);
begin
  Stream.WriteBuffer(V, 1);
end;

procedure WriteU16(Stream: TStream; V: Word);
var Raw: Word;
begin
  Raw := ToBE16(V);
  Stream.WriteBuffer(Raw, 2);
end;

procedure WriteU32(Stream: TStream; V: Cardinal);
var Raw: Cardinal;
begin
  Raw := ToBE32(V);
  Stream.WriteBuffer(Raw, 4);
end;

function ReadFixedString(Stream: TStream; Len: Integer): string;
var
  Buf: TBytes;
  I: Integer;
begin
  SetLength(Buf, Len);
  Stream.ReadBuffer(Buf[0], Len);
  I := 0;
  while (I < Len) and (Buf[I] <> 0) do
    Inc(I);
  Result := TEncoding.ANSI.GetString(Buf, 0, I);
end;

procedure WriteFixedString(Stream: TStream; const S: string; Len: Integer);
var
  Buf: TBytes;
  Src: TBytes;
  N: Integer;
begin
  SetLength(Buf, Len);            // zero-filled
  FillChar(Buf[0], Len, 0);
  Src := TEncoding.ANSI.GetBytes(S);
  N := Length(Src);
  if N > Len then
    N := Len;                     // truncate; leaves room for null
  if N > 0 then
    Move(Src[0], Buf[0], N);
  Stream.WriteBuffer(Buf[0], Len);
end;

{ ---- Date conversion (Palm epoch = 1904-01-01) ---- }

function PalmDateToDateTime(Seconds: Cardinal): TDateTime;
const
  SecondsPerDay = 86400.0;
begin
  if Seconds = 0 then
    Exit(0);
    if (Seconds and $80000000) = 0 then
      Result := EncodeDate(1970, 1, 1) + (Seconds / SecondsPerDay)
    else
      Result := EncodeDate(1904, 1, 1) + (Seconds / SecondsPerDay)
end;

function DateTimeToPalmDate(DT: TDateTime): Cardinal;
const
  SecondsPerDay = 86400.0;
var
  Base: TDateTime;
begin
  if DT = 0 then
    Exit(0);
  Base := EncodeDate(1904, 1, 1);
  if DT < Base then
    Exit(0);
  Result := Round((DT - Base) * SecondsPerDay);
end;

{ ============================================================
  TPDBRecord
  ============================================================ }

function TPDBRecord.IsDeleted: Boolean; begin Result := (Attributes and $80) <> 0; end;
function TPDBRecord.IsDirty: Boolean;   begin Result := (Attributes and $40) <> 0; end;

constructor TPDBRecord.Create;
begin
  inherited create;
  FVexed := Nil;
end;

procedure TPDBRecord.DecodeVexedData;
var
  Buf: TByteBuffer;
  RunLength: Integer;
  Marker: Word;
  Section, Key, Value: String;
  LInfo: TVexedInfo;
  LLevel: TVexedLevel;
  LastRec: Boolean;
  EOL: Byte;
begin
  var dbg: Integer := 0;

  if not Assigned(Data) then
    begin
      if Assigned(FVexed) then
        FreeAndNil(FVexed);
      exit;
    end;

  if Assigned(FVexed) then
    FreeAndNil(FVexed);

  FVexed := TVexedPack.Create;

  Buf := TByteBuffer.Create(Data);
  try
    try
      // Read Runlength
      RunLength := Integer(Buf.ReadWord);
      // Read Marker
      Marker := Buf.ReadWord;
      // It appears Marker is always 3
      if Marker <> 3 then
        Raise EVexedError.Create('Bad Marker');
      // Update RunLength subtracting 2 Words just read
      RunLength := RunLength - (2 * SizeOf(Word));
      // Read the Section
      Section := Buf.ReadString;
      if Section <> 'General' then
        Raise EVexedError.Create('Bad General Section Name');
      // Update RunLength. subtract chars in Section + 1 (terminating null)
      RunLength := RunLength - (Length(Section) + 1);

      LInfo := TVexedInfo.Create;
      while(RunLength > 0) do
        begin
          // Read the Key
          Key := Buf.ReadString;
          // Update RunLength. subtract chars in Key + 1 (terminating null)
          RunLength := RunLength - (Length(Key) + 1);
          if RunLength <= 0 then
            Raise EVexedError.Create('Read Error');
          // Read the Key
          Value := Buf.ReadString;
          // Update RunLength. subtract chars in Value + 1 (terminating null)
          RunLength := RunLength - (Length(Value) + 1);
          if Key = 'Author' then
            LInfo.SetAuthor(Value)
          else if Key = 'Description' then
            LInfo.SetDescription(Value)
          else if Key = 'URL' then
            LInfo.SetUrl(Value)
          else
            Raise EVexedError.Create('Unhandled Info Key/Value');
        end;
        FVexed.AddInfo(LInfo);
        LInfo.Free;

      if Buf.FPosition < Buf.FSize then
        begin
          LastRec := False;

          while not LastRec do
            begin
              // Read Runlength
              RunLength := Integer(Buf.ReadWord);
              // Runlength is zero on last record
              if RunLength = 0 then
                begin
                  RunLength := Buf.FSize - Buf.FPosition;
                  LastRec := True;
                end;

              // Read Marker
              Marker := Buf.ReadWord;
              // It appears Marker is always 3
              if Marker <> 3 then
                Raise EVexedError.Create('Bad Marker');
              // Update RunLength subtracting 2 Words just read
              RunLength := RunLength - (2 * SizeOf(Word));
              // Read the Section
              Section := Buf.ReadString;
              if Section <> 'Level' then
                Raise EVexedError.Create('Bad Level Section Name');
              // Update RunLength. subtract chars in Section + 1 (terminating null)
              RunLength := RunLength - (Length(Section) + 1);

              LLevel := TVexedLevel.Create;
              while(RunLength > 1) do
                begin
                  // Read the Key
                  Key := Buf.ReadString;
                  // Update RunLength. subtract chars in Key + 1 (terminating null)
                  RunLength := RunLength - (Length(Key) + 1);
                  if RunLength <= 0 then
                    Raise EVexedError.Create('Read Error');
                  // Read the Key
                  Value := Buf.ReadString;
                  // Update RunLength. subtract chars in Value + 1 (terminating null)
                  RunLength := RunLength - (Length(Value) + 1);
                  if Key = 'board' then
                    LLevel.SetBoard(Value)
                  else if Key = 'solution' then
                    LLevel.SetSolution(Value)
                  else if Key = 'title' then
                    LLevel.SetTitle(Value)
                  else
                    Raise EVexedError.Create('Unhandled Level Key/Value');
                end;

              if (RunLength > 0) then
                begin
                  EOL := Buf.ReadByte; // sbdbg
                  RunLength := RunLength - SizeOf(Byte);
                end;


              FVexed.AddLevel(LLevel);
              Inc(dbg);
              if dbg = 58 then
                LastRec := False;

              // LLevel.Free;

            end;
        end;


    except
      FreeAndNil(FVexed);
    end;

  finally
    Buf.Free;
  end;

end;

destructor TPDBRecord.Destroy;
begin
  if Assigned(FVexed) then
    FreeAndNil(FVexed);

  inherited;
end;

function TPDBRecord.IsBusy: Boolean;    begin Result := (Attributes and $20) <> 0; end;
function TPDBRecord.IsSecret: Boolean;  begin Result := (Attributes and $10) <> 0; end;

{ ============================================================
  TPDBFile
  ============================================================ }

constructor TPDBFile.Create;
begin
  inherited Create;
  FRecords := TObjectList<TPDBRecord>.Create(True);
end;

destructor TPDBFile.Destroy;
begin
  FRecords.Free;
  inherited;
end;

function TPDBFile.GetRecord(Index: Integer): TPDBRecord;
begin
  Result := FRecords[Index];
end;

function TPDBFile.GetRecordCount: Integer;
begin
  Result := FRecords.Count;
end;

function TPDBFile.IsResourceDatabase: Boolean;
begin
  Result := (Attributes and dmHdrAttrResDB) <> 0;
end;

function TPDBFile.AddRecord: TPDBRecord;
begin
  Result := TPDBRecord.Create;
  Result.DecodeVexedData;
  FRecords.Add(Result);
end;

{ ---- Loading ---- }

procedure TPDBFile.LoadFromStream(Stream: TStream);
var
  I: Integer;
  NumRecords: Word;
  RecOffsets: array of Cardinal;
  RecAttribs: array of Byte;
  RecUniqueIDs: array of Cardinal;
  IDBuf: array[0..3] of Byte;
  DataStart, DataEnd, DataLen: Cardinal;
  Rec: TPDBRecord;
  FileSize: Int64;
begin
  FRecords.Clear;
  FileSize := Stream.Size;
  if FileSize < PDB_HEADER_SIZE + RECLIST_HDR_SIZE then
    raise Exception.Create('File too small to be a valid PDB.');

  { ----- Header ----- }
  Name := ReadFixedString(Stream, 32);
  Attributes := ReadU16(Stream);
  Version := ReadU16(Stream);
  CreationDate := PalmDateToDateTime(ReadU32(Stream));
  ModificationDate := PalmDateToDateTime(ReadU32(Stream));
  LastBackupDate := PalmDateToDateTime(ReadU32(Stream));
  ModificationNumber := ReadU32(Stream);
  AppInfoID := ReadU32(Stream);
  SortInfoID := ReadU32(Stream);
  DBType := ReadFixedString(Stream, 4);
  Creator := ReadFixedString(Stream, 4);
  UniqueIDSeed := ReadU32(Stream);

  { ----- Record list header ----- }
  ReadU32(Stream);                 // nextRecordListID (ignored, expect 0)
  NumRecords := ReadU16(Stream);

  SetLength(RecOffsets, NumRecords);
  SetLength(RecAttribs, NumRecords);
  SetLength(RecUniqueIDs, NumRecords);

  for I := 0 to NumRecords - 1 do
  begin
    RecOffsets[I] := ReadU32(Stream);
    Stream.ReadBuffer(IDBuf[0], 4);
    RecAttribs[I] := IDBuf[0];
    RecUniqueIDs[I] := (Cardinal(IDBuf[1]) shl 16) or
                       (Cardinal(IDBuf[2]) shl 8)  or
                        Cardinal(IDBuf[3]);
  end;

  { ----- AppInfo / SortInfo ----- }
  AppInfoBlock := nil;
  SortInfoBlock := nil;

  if AppInfoID > 0 then
  begin
    if SortInfoID > 0 then
      DataEnd := SortInfoID
    else if NumRecords > 0 then
      DataEnd := RecOffsets[0]
    else
      DataEnd := Cardinal(FileSize);
    if DataEnd > AppInfoID then
    begin
      DataLen := DataEnd - AppInfoID;
      SetLength(AppInfoBlock, DataLen);
      Stream.Position := AppInfoID;
      Stream.ReadBuffer(AppInfoBlock[0], DataLen);
    end;
  end;

  if SortInfoID > 0 then
  begin
    if NumRecords > 0 then
      DataEnd := RecOffsets[0]
    else
      DataEnd := Cardinal(FileSize);
    if DataEnd > SortInfoID then
    begin
      DataLen := DataEnd - SortInfoID;
      SetLength(SortInfoBlock, DataLen);
      Stream.Position := SortInfoID;
      Stream.ReadBuffer(SortInfoBlock[0], DataLen);
    end;
  end;

  { ----- Record data ----- }
  for I := 0 to NumRecords - 1 do
  begin
    DataStart := RecOffsets[I];
    if I < NumRecords - 1 then
      DataEnd := RecOffsets[I + 1]
    else
      DataEnd := Cardinal(FileSize);

    if (DataEnd < DataStart) or (DataStart > FileSize) then
      raise Exception.CreateFmt('Corrupt record offsets at record %d.', [I]);

    DataLen := DataEnd - DataStart;
    Rec := TPDBRecord.Create;
    Rec.Attributes := RecAttribs[I];
    Rec.UniqueID := RecUniqueIDs[I];
    SetLength(Rec.Data, DataLen);
    if DataLen > 0 then
    begin
      Stream.Position := DataStart;
      Stream.ReadBuffer(Rec.Data[0], DataLen);
      Rec.DecodeVexedData;
    end;
    FRecords.Add(Rec);
  end;
end;

procedure TPDBFile.LoadFromFile(const AFileName: string);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    LoadFromStream(Stream);
  finally
    Stream.Free;
  end;
end;

{ ---- Saving ----

  Layout produced:
    [header 78][record list hdr 6][record entries N*8]
    [2 pad bytes]           <- conventional gap after record list
    [AppInfo][SortInfo]
    [record data ...]

  All offsets are computed here so callers never manage them. }

procedure TPDBFile.SaveToStream(Stream: TStream);
const
  RECLIST_GAP = 2; // traditional 2-byte filler between list and data
var
  I: Integer;
  NumRecords: Word;
  AppInfoID, SortInfoID: Cardinal;
  Cursor: Cardinal;                 // running offset of the data region
  RecOffsets: array of Cardinal;
  Attr: Byte;
  UID: Cardinal;
begin
  NumRecords := FRecords.Count;
  SetLength(RecOffsets, NumRecords);

  { Compute where variable data begins. }
  Cursor := PDB_HEADER_SIZE + RECLIST_HDR_SIZE +
            Cardinal(NumRecords) * RECLIST_ENTRY_SIZE + RECLIST_GAP;

  if Length(AppInfoBlock) > 0 then
  begin
    AppInfoID := Cursor;
    Inc(Cursor, Length(AppInfoBlock));
  end
  else
    AppInfoID := 0;

  if Length(SortInfoBlock) > 0 then
  begin
    SortInfoID := Cursor;
    Inc(Cursor, Length(SortInfoBlock));
  end
  else
    SortInfoID := 0;

  for I := 0 to NumRecords - 1 do
  begin
    RecOffsets[I] := Cursor;
    Inc(Cursor, Length(FRecords[I].Data));
  end;

  { ----- Header ----- }
  WriteFixedString(Stream, Name, 32);
  WriteU16(Stream, Attributes);
  WriteU16(Stream, Version);
  WriteU32(Stream, DateTimeToPalmDate(CreationDate));
  WriteU32(Stream, DateTimeToPalmDate(ModificationDate));
  WriteU32(Stream, DateTimeToPalmDate(LastBackupDate));
  WriteU32(Stream, ModificationNumber);
  WriteU32(Stream, AppInfoID);
  WriteU32(Stream, SortInfoID);
  WriteFixedString(Stream, DBType, 4);
  WriteFixedString(Stream, Creator, 4);
  WriteU32(Stream, UniqueIDSeed);

  { ----- Record list header ----- }
  WriteU32(Stream, 0);              // nextRecordListID
  WriteU16(Stream, NumRecords);

  { ----- Record list entries ----- }
  for I := 0 to NumRecords - 1 do
  begin
    WriteU32(Stream, RecOffsets[I]);
    Attr := FRecords[I].Attributes;
    UID  := FRecords[I].UniqueID;
    WriteU8(Stream, Attr);
    WriteU8(Stream, (UID shr 16) and $FF);
    WriteU8(Stream, (UID shr 8) and $FF);
    WriteU8(Stream, UID and $FF);
  end;

  { ----- Gap ----- }
  WriteU16(Stream, 0);

  { ----- AppInfo / SortInfo ----- }
  if Length(AppInfoBlock) > 0 then
    Stream.WriteBuffer(AppInfoBlock[0], Length(AppInfoBlock));
  if Length(SortInfoBlock) > 0 then
    Stream.WriteBuffer(SortInfoBlock[0], Length(SortInfoBlock));

  { ----- Record data ----- }
  for I := 0 to NumRecords - 1 do
    if Length(FRecords[I].Data) > 0 then
      Stream.WriteBuffer(FRecords[I].Data[0], Length(FRecords[I].Data));
end;

procedure TPDBFile.SaveToFile(const AFileName: string);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(AFileName, fmCreate);
  try
    SaveToStream(Stream);
  finally
    Stream.Free;
  end;
end;

{ ---- Convenience ---- }

function DecodePDBFile(const AFileName: string): TPDBFile;
begin
  Result := TPDBFile.Create;
  try
    Result.LoadFromFile(AFileName);
  except
    Result.Free;
    raise;
  end;
end;

{ TVexedPack }

procedure TVexedPack.AddInfo(AValue: TVexedInfo);
begin
  Finfo.SetAuthor(AValue.Author);
  Finfo.SetUrl(AValue.Url);
  Finfo.SetDescription(AValue.Description);
end;

procedure TVexedPack.AddLevel(ALevel: TVexedLevel);
begin
  FLevels.Add(ALevel);
end;

constructor TVexedPack.Create;
begin
  inherited Create;

  FInfo := TVexedInfo.Create;
  FLevels := TObjectList<TVexedLevel>.Create(True);

end;

destructor TVexedPack.Destroy;
begin
  FLevels.Free;
  FInfo.Free;

  inherited;
end;

function TVexedPack.GetLevel(Index: Integer): TVexedLevel;
begin
  Result := FLevels[Index];
end;

function TVexedPack.GetLevelCount: Integer;
begin
  Result := FLevels.Count;
end;

{ TVexedInfo }

procedure TVexedInfo.SetAuthor(const AValue: String);
begin
  if AValue <> FAuthor then
    FAuthor := AValue;
end;

procedure TVexedInfo.SetDescription(const AValue: String);
begin
  if AValue <> FDescription then
    FDescription := AValue;
end;

procedure TVexedInfo.SetUrl(const AValue: String);
begin
  if AValue <> FUrl then
    FUrl := AValue;
end;

{ TVexedLevel }

procedure TVexedLevel.SetBoard(const AValue: String);
begin
  if AValue <> FBoard then
    FBoard := AValue;
end;

procedure TVexedLevel.SetSolution(const AValue: String);
begin
  if AValue <> FSolution then
    FSolution := AValue;
end;

procedure TVexedLevel.SetTitle(const AValue: String);
begin
  if AValue <> FTitle then
    FTitle := AValue;
end;

end.
