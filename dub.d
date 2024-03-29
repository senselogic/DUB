/*
    This file is part of the Dub distribution.

    https://github.com/senselogic/DUB

    Copyright (C) 2020 Eric Pelzer (ecstatic.coder@gmail.com)

    Dub is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, version 3.

    Dub is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Dub.  If not, see <http://www.gnu.org/licenses/>.
*/

// -- IMPORTS

import core.stdc.stdlib : exit;
import core.time : msecs, Duration;
import std.algorithm : countUntil, sort;
import std.conv : parse, to;
import std.datetime : hnsecs, Clock, SysTime, UTC;
import std.digest : toHexString;
import std.digest.sha : SHA256;
import std.file : copy, dirEntries, exists, getAttributes, getSize, getTimes, mkdir, mkdirRecurse, read, readText, remove, rename, rmdir, setAttributes, setTimes, write, PreserveAttributes, SpanMode;
import std.format : format;
import std.path : globMatch;
import std.stdio : readln, writeln, File;
import std.string : endsWith, indexOf, join, lastIndexOf, replace, split, startsWith, toLower, toUpper;

// -- CONSTANTS

const uint
    NoFolderIndex = -1;
const string[]
    HexadecimalDigitArray = [ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F" ];

// -- TYPES

alias HASH = ubyte[ 32 ];

// ~~

class BUFFER
{
    // -- ATTRIBUTES

    ubyte[]
        ByteArray;
    ulong
        ByteIndex;
    string[]
        TagArray;
    ulong[ string ]
        TagIndexMap;

    // -- INQUIRIES

    bool IsRead(
        )
    {
        return ByteIndex == ByteArray.length;
    }

    // -- OPERATIONS

    void Clear(
        )
    {
        ByteArray.length = 0;
        ByteIndex = 0;
    }

    // ~~

    void WriteBoolean(
        bool boolean
        )
    {
        ByteArray ~= boolean ? 1 : 0;
    }

    // ~~

    void WriteByte(
        ubyte byte_
        )
    {
        ByteArray ~= byte_;
    }

    // ~~

    void WriteNatural16(
        ushort natural
        )
    {
        WriteNatural64( natural );
    }

    // ~~

    void WriteNatural32(
        uint natural
        )
    {
        WriteNatural64( natural );
    }

    // ~~

    void WriteNatural64(
        ulong natural
        )
    {
        while ( natural > 127 )
        {
            ByteArray ~= cast( ubyte )( 128 | ( natural & 127 ) );

            natural >>= 7;
        }

        ByteArray ~= cast( ubyte )( natural & 127 );
    }

    // ~~

    void WriteInteger64(
        long integer
        )
    {
        ulong
            natural;

        natural = ( ( cast( ulong )integer ) & 0x7FFFFFFFFFFFFFFF ) << 1;

        if ( integer < 0 )
        {
            natural = ~natural | 1;
        }

        WriteNatural64( natural );
    }

    // ~~

    void WriteHash(
        HASH hash
        )
    {
        ByteArray ~= hash;
    }

    // ~~

    void WriteText(
        string text
        )
    {
        WriteNatural64( text.length );
        ByteArray ~= cast( ubyte[] )text[ 0 .. $ ];
    }

    // ~~

    void WriteTag(
        string tag
        )
    {
        ulong *
            found_tag_index;

        found_tag_index = tag in TagIndexMap;

        if ( found_tag_index !is null )
        {
            WriteNatural64( ( *found_tag_index << 1 ) | 1 );
        }
        else
        {
            TagIndexMap[ tag ] = TagArray.length;
            TagArray ~= tag;

            WriteNatural64( tag.length << 1 );
            ByteArray ~= cast( ubyte[] )tag[ 0 .. $ ];
        }
    }

    // ~~

    void SaveFile(
        string file_path
        )
    {
        file_path.WriteByteArray( ByteArray );
    }

    // ~~

    bool ReadBoolean(
        )
    {
        return ReadByte() != 0;
    }

    // ~~

    ubyte ReadByte(
        )
    {
        return ByteArray[ ByteIndex++ ];
    }

    // ~~

    ushort ReadNatural16(
        )
    {
        return cast( ushort )ReadNatural64();
    }

    // ~~

    uint ReadNatural32(
        )
    {
        return cast( uint )ReadNatural64();
    }

    // ~~

    ulong ReadNatural64(
        )
    {
        uint
            bit_count;
        ulong
            byte_,
            natural;

        natural = 0;
        bit_count = 0;

        do
        {
            byte_ = cast( ulong )ReadByte();
            natural |= ( byte_ & 127 ) << bit_count;
            bit_count += 7;
        }
        while ( ( byte_ & 128 ) != 0 );

        return natural;
    }

    // ~~

    long ReadInteger64(
        )
    {
        ulong
            natural;

        natural = ReadNatural64();

        if ( ( natural & 1 ) == 0 )
        {
            return cast( long )( natural >> 1 );
        }
        else
        {
            return cast( long )( ~( natural >> 1 ) | 0x8000000000000000 );
        }
    }

    // ~~

    HASH ReadHash(
        )
    {
        ByteIndex += 32;

        return ByteArray[ ByteIndex - 32 .. ByteIndex ][ 0 .. 32 ];
    }

    // ~~

    string ReadText(
        )
    {
        ulong
            character_count;

        character_count = ReadNatural64();
        ByteIndex += character_count;

        return ( cast( char[] )ByteArray[ ByteIndex - character_count .. ByteIndex ] ).to!string();
    }

    // ~~

    string ReadTag(
        )
    {
        string
            tag;
        ulong
            character_count,
            natural;

        natural = ReadNatural64();

        if ( ( natural & 1 ) == 0 )
        {
            character_count = natural >> 1;

            ByteIndex += character_count;
            tag = ( cast( char[] )ByteArray[ ByteIndex - character_count .. ByteIndex ] ).to!string();

            TagIndexMap[ tag ] = TagArray.length;
            TagArray ~= tag;

            return tag;
        }
        else
        {
            return TagArray[ natural >> 1 ];
        }
    }

    // ~~

    bool HasTag(
        string tag
        )
    {
        string
            found_tag;
        ulong
            byte_index;

        byte_index = ByteIndex;
        found_tag = ReadTag();

        if ( found_tag == tag )
        {
            return true;
        }
        else
        {
            ByteIndex = byte_index;

            return false;
        }
    }


    // ~~

    void LoadFile(
        string file_path
        )
    {
        ByteArray = file_path.ReadByteArray();
        ByteIndex = 0;
    }
}

// ~~

class STREAM : BUFFER
{
    // -- ATTRIBUTES

    BUFFER
        SectionBuffer;

    // -- CONSTRUCTORS

    this(
        )
    {
        SectionBuffer = new BUFFER();
    }

    // -- OPERATIONS

    void WriteSection(
        string tag = ""
        )
    {
        if ( ByteArray.length > 0 )
        {
            SectionBuffer.WriteNatural64( ByteArray.length );
            SectionBuffer.ByteArray ~= ByteArray;
            ByteArray.length = 0;
        }

        if ( tag != "" )
        {
            SectionBuffer.WriteTag( tag );
        }
    }

    // ~~

    override void SaveFile(
        string file_path
        )
    {
        file_path.WriteByteArray( SectionBuffer.ByteArray );
    }
    // ~~

    bool ReadSection(
        string tag
        )
    {
        ulong
            section_byte_count;

        if ( HasTag( tag ) )
        {
            section_byte_count = ReadNatural64();

            return true;
        }
        else
        {
            writeln( "Missing tag : ", tag, " (", ByteIndex, ")" );

            return false;
        }
    }
}

// ~~

class SNAPSHOT_FOLDER
{
    // -- ATTRIBUTES

    uint
        SuperFolderIndex;
    string
        Name;
    ulong
        AccessTime,
        ModificationTime;
    uint
        AttributeMask;
    string
        Path;
    SNAPSHOT_FILE[]
        FileArray;
    SNAPSHOT_FILE[ string ]
        FileMap;

    // -- OPERATIONS

    void Write(
        STREAM stream
        )
    {
        stream.WriteNatural32( SuperFolderIndex );
        stream.WriteText( Name );
        stream.WriteNatural64( AccessTime );
        stream.WriteNatural64( ModificationTime );
        stream.WriteNatural32( AttributeMask );
    }

    // ~~

    void Read(
        STREAM stream
        )
    {
        SuperFolderIndex = stream.ReadNatural32();
        Name = stream.ReadText();
        AccessTime = stream.ReadNatural64();
        ModificationTime = stream.ReadNatural64();
        AttributeMask = stream.ReadNatural32();
    }
}

// ~~

class SNAPSHOT_FILE
{
    // -- ATTRIBUTES

    SNAPSHOT_FOLDER
        Folder;
    uint
        FolderIndex;
    string
        Name;
    HASH
        Hash;
    ulong
        ByteCount,
        AccessTime,
        ModificationTime;
    uint
        AttributeMask;

    // -- INQUIRIES

    string GetFilePath(
        )
    {
        return Folder.Path ~ Name;
    }

    // ~~

    string GetStoreName(
        )
    {
        return
            cast( string )Hash.toHexString()
            ~ "_"
            ~ format( "%x", ByteCount ).toUpper();
    }

    // ~~

    string GetStoreFileName(
        )
    {
        return GetStoreName() ~ ".dbf";
    }

    // ~~

    string GetStoreFilePath(
        )
    {
        ulong
            first_hash,
            second_hash;

        first_hash = Hash[ 0 ] >> 2;
        second_hash = ( ( Hash[ 0 ] << 4 ) & 255 ) | ( Hash[ 1 ] >> 4 );

        return
            HexadecimalDigitArray[ first_hash >> 4 ]
            ~ HexadecimalDigitArray[ first_hash & 15 ]
            ~ "/"
            ~ HexadecimalDigitArray[ second_hash >> 4 ]
            ~ HexadecimalDigitArray[ second_hash & 15 ]
            ~ "/"
            ~ GetStoreFileName();
    }

    // ~~

    bool IsSame(
        SNAPSHOT_FILE snapshot_file
        )
    {
        return
            ByteCount == snapshot_file.ByteCount
            && ModificationTime == snapshot_file.ModificationTime;
    }

    // -- OPERATIONS

    void HashDataFile(
        string data_file_path
        )
    {
        File
            file;
        SysTime
            access_time,
            modification_time;
        HASH
            hash;
        SHA256
            sha256;

        if ( VerboseOptionIsEnabled )
        {
            writeln( "Hashing data file : ", data_file_path );
        }

        try
        {
            file = File( data_file_path );

            foreach ( byte_array; file.byChunk( 32 * 1024 * 1024 ) )
            {
                sha256.put( byte_array );
            }

            Hash = sha256.finish();
            ByteCount = data_file_path.getSize();
            data_file_path.getTimes( access_time, modification_time );
            AccessTime = access_time.GetTime(),
            ModificationTime = modification_time.GetTime();
            AttributeMask = data_file_path.getAttributes();
        }
        catch ( Exception exception )
        {
            Abort( "Can't hash data file : " ~ data_file_path, exception, false );
        }
    }

    void Write(
        STREAM stream
        )
    {
        stream.WriteNatural32( FolderIndex );
        stream.WriteText( Name );
        stream.WriteHash( Hash );
        stream.WriteNatural64( ByteCount );
        stream.WriteNatural64( AccessTime );
        stream.WriteNatural64( ModificationTime );
        stream.WriteNatural32( AttributeMask );
    }

    // ~~

    void Read(
        STREAM stream
        )
    {
        FolderIndex = stream.ReadNatural32();
        Name = stream.ReadText();
        Hash = stream.ReadHash();
        ByteCount = stream.ReadNatural64();
        AccessTime = stream.ReadNatural64();
        ModificationTime = stream.ReadNatural64();
        AttributeMask = stream.ReadNatural32();
    }
}

// ~~

class SNAPSHOT
{
    // -- ATTRIBUTES

    uint
        Version;
    ulong
        Time;
    string
        DataFolderPath;
    string[]
        FolderFilterArray;
    bool[]
        FolderFilterIsInclusiveArray;
    string[]
        FileFilterArray;
    bool[]
        FileFilterIsInclusiveArray;
    string[]
        SelectedFileFilterArray;
    SNAPSHOT_FOLDER[]
        FolderArray;
    SNAPSHOT_FOLDER[ string ]
        FolderMap;
    SNAPSHOT_FILE[]
        FileArray;

    // -- INQUIRIES

    string GetFileName(
        )
    {
        return Time.GetTimeStamp() ~ ".dbs";
    }

    // ~~

    SNAPSHOT_FOLDER GetFolder(
        string folder_path
        )
    {
        SNAPSHOT_FOLDER *
            snapshot_folder;

        snapshot_folder = folder_path in FolderMap;

        if ( snapshot_folder !is null )
        {
            return *snapshot_folder;
        }
        else
        {
            return null;
        }
    }

    // ~~

    SNAPSHOT_FOLDER GetFolder(
        SNAPSHOT_FOLDER snapshot_folder
        )
    {
        return GetFolder( snapshot_folder.Path );
    }

    // ~~

    bool HasFolder(
        SNAPSHOT_FOLDER snapshot_folder
        )
    {
        return GetFolder( snapshot_folder.Path ) !is null;
    }

    // ~~

    SNAPSHOT_FILE GetFile(
        string folder_path,
        string file_name
        )
    {
        SNAPSHOT_FILE *
            snapshot_file;
        SNAPSHOT_FOLDER *
            snapshot_folder;

        snapshot_folder = folder_path in FolderMap;

        if ( snapshot_folder !is null )
        {
            snapshot_file = file_name in snapshot_folder.FileMap;

            if ( snapshot_file !is null )
            {
                return *snapshot_file;
            }
            else
            {
                return null;
            }
        }
        else
        {
            return null;
        }
    }

    // ~~

    SNAPSHOT_FILE GetFile(
        SNAPSHOT_FILE snapshot_file
        )
    {
        return GetFile( snapshot_file.Folder.Path, snapshot_file.Name );
    }

    // ~~

    bool HasFile(
        SNAPSHOT_FILE snapshot_file
        )
    {
        return GetFile( snapshot_file.Folder.Path, snapshot_file.Name ) !is null;
    }

    // ~~

    SNAPSHOT_FILE GetSameFile(
        SNAPSHOT_FILE snapshot_file
        )
    {
        SNAPSHOT_FILE
            found_snapshot_file;

        found_snapshot_file = GetFile( snapshot_file.Folder.Path, snapshot_file.Name );

        if ( found_snapshot_file !is null
             && found_snapshot_file.IsSame( snapshot_file ) )
        {
            return found_snapshot_file;
        }
        else
        {
            return null;
        }
    }

    // -- OPERATIONS

    void ScanFolder(
        string folder_path,
        ulong folder_access_time,
        ulong folder_modification_time,
        uint folder_attribute_mask,
        uint super_folder_index
        )
    {
        uint
            folder_index;
        string
            file_name,
            file_path,
            relative_file_path,
            relative_folder_path;
        SNAPSHOT_FOLDER
            snapshot_folder;
        SNAPSHOT_FILE
            snapshot_file;

        relative_folder_path = GetRelativePath( folder_path );

        if ( IsIncludedFolder( "/" ~ relative_folder_path ) )
        {
            if ( VerboseOptionIsEnabled )
            {
                writeln( "Scanning data folder : ", DataFolderPath, relative_folder_path );
            }

            snapshot_folder = new SNAPSHOT_FOLDER();
            snapshot_folder.SuperFolderIndex = super_folder_index;
            snapshot_folder.Name = relative_folder_path.GetFolderName();
            snapshot_folder.AccessTime = folder_access_time;
            snapshot_folder.ModificationTime = folder_modification_time;
            snapshot_folder.AttributeMask = folder_attribute_mask;
            snapshot_folder.Path = relative_folder_path;
            folder_index = cast( uint )FolderArray.length;
            FolderArray ~= snapshot_folder;
            FolderMap[ snapshot_folder.Path ] = snapshot_folder;

            try
            {
                foreach ( folder_entry; dirEntries( folder_path, SpanMode.shallow ) )
                {
                    if ( folder_entry.isFile
                         && !folder_entry.isSymlink )
                    {
                        file_path = folder_entry.name.GetLogicalPath();
                        file_name = file_path.GetFileName();
                        relative_file_path = GetRelativePath( folder_entry );

                        if ( IsIncludedFile( "/" ~ relative_folder_path, "/" ~ relative_file_path, file_name )
                             && IsSelectedFile( "/" ~ relative_folder_path, "/" ~ relative_file_path, file_name ) )
                        {
                            if ( VerboseOptionIsEnabled )
                            {
                                writeln( "Scanning data file : ", file_path );
                            }

                            snapshot_file = new SNAPSHOT_FILE();
                            snapshot_file.Folder = FolderArray[ folder_index ];
                            snapshot_file.FolderIndex = folder_index;
                            snapshot_file.Name = file_name;
                            snapshot_file.AccessTime = folder_entry.timeLastAccessed.GetTime();
                            snapshot_file.ModificationTime = folder_entry.timeLastModified.GetTime();
                            snapshot_file.AttributeMask = folder_entry.attributes;
                            snapshot_file.ByteCount = folder_entry.size;

                            snapshot_folder.FileArray ~= snapshot_file;
                            snapshot_folder.FileMap[ file_name ] = snapshot_file;

                            FileArray ~= snapshot_file;
                        }
                    }
                }

                foreach ( folder_entry; dirEntries( folder_path, SpanMode.shallow ) )
                {
                    if ( folder_entry.isDir
                         && !folder_entry.isSymlink )
                    {
                        ScanFolder(
                            folder_entry.name.GetLogicalPath() ~ '/',
                            folder_entry.timeLastAccessed.GetTime(),
                            folder_entry.timeLastModified.GetTime(),
                            folder_entry.attributes,
                            folder_index
                            );
                    }
                }
            }
            catch ( Exception exception )
            {
                Abort( "Can't scan folder : " ~ folder_path );
            }
        }
    }

    // ~~

    void ScanFolder(
        string folder_path
        )
    {
        uint
            attribute_mask;
        SysTime
            access_time,
            modification_time;

        attribute_mask = folder_path.getAttributes();
        folder_path.getTimes( access_time, modification_time );

        ScanFolder(
            folder_path,
            access_time.GetTime(),
            modification_time.GetTime(),
            attribute_mask,
            NoFolderIndex
            );
    }

    // ~~

    void ScanDataFolder(
        )
    {
        Version = 1;
        Time = Clock.currTime().GetTime();
        DataFolderPath = .DataFolderPath;
        FolderFilterArray = .FolderFilterArray.dup();
        FolderFilterIsInclusiveArray = .FolderFilterIsInclusiveArray.dup();
        FileFilterArray = .FileFilterArray.dup();
        FileFilterIsInclusiveArray = .FileFilterIsInclusiveArray.dup();
        SelectedFileFilterArray = .SelectedFileFilterArray.dup();

        if ( !DataFolderPath.exists() )
        {
            if ( BackupOptionIsEnabled )
            {
                Abort( "Missing data folder : " ~ DataFolderPath );
            }
            else
            {
                DataFolderPath.AddFolder( true );
            }
        }

        ScanFolder( DataFolderPath );
    }

    // ~~

    void SaveFile(
        string file_path
        )
    {
        STREAM
            stream;

        writeln( "Writing snapshot file : ", file_path );

        stream = new STREAM();

        stream.WriteSection( "Version" );
        stream.WriteNatural32( Version );

        stream.WriteSection( "Time" );
        stream.WriteNatural64( Time );

        stream.WriteSection( "DataFolderPath" );
        stream.WriteText( DataFolderPath );

        stream.WriteSection( "FolderFilterArray" );
        stream.WriteNatural32( cast( uint )FolderFilterArray.length );

        foreach ( folder_filter; FolderFilterArray )
        {
            stream.WriteText( folder_filter );
        }

        stream.WriteSection( "FolderFilterIsInclusiveArray" );
        stream.WriteNatural32( cast( uint )FolderFilterIsInclusiveArray.length );

        foreach ( folder_filter_is_inclusive; FolderFilterIsInclusiveArray )
        {
            stream.WriteBoolean( folder_filter_is_inclusive );
        }

        stream.WriteSection( "FileFilterArray" );
        stream.WriteNatural32( cast( uint )FileFilterArray.length );

        foreach ( file_filter; FileFilterArray )
        {
            stream.WriteText( file_filter );
        }

        stream.WriteSection( "FileFilterIsInclusiveArray" );
        stream.WriteNatural32( cast( uint )FileFilterIsInclusiveArray.length );

        foreach ( file_filter_is_inclusive; FileFilterIsInclusiveArray )
        {
            stream.WriteBoolean( file_filter_is_inclusive );
        }

        stream.WriteSection( "SelectedFileFilterArray" );
        stream.WriteNatural32( cast( uint )SelectedFileFilterArray.length );

        foreach ( selected_file_filter; SelectedFileFilterArray )
        {
            stream.WriteText( selected_file_filter );
        }

        stream.WriteSection( "FolderArray" );
        stream.WriteNatural32( cast( uint )FolderArray.length );

        foreach ( snapshot_folder; FolderArray )
        {
            snapshot_folder.Write( stream );
        }

        stream.WriteSection( "FileArray" );
        stream.WriteNatural32( cast( uint )FileArray.length );

        foreach ( snapshot_file; FileArray )
        {
            snapshot_file.Write( stream );
        }

        stream.WriteSection();
        stream.SaveFile( file_path );
    }

    // ~~

    void LoadFile(
        string file_path
        )
    {
        long
            file_count,
            file_filter_count,
            file_filter_index,
            file_filter_is_inclusive_count,
            file_filter_is_inclusive_index,
            file_index,
            folder_count,
            folder_filter_count,
            folder_filter_index,
            folder_filter_is_inclusive_count,
            folder_filter_is_inclusive_index,
            folder_index,
            name_count,
            name_index,
            selected_file_filter_count,
            selected_file_filter_index;
        SNAPSHOT_FILE
            snapshot_file;
        SNAPSHOT_FOLDER
            snapshot_folder;
        STREAM
            stream;

        writeln( "Reading snapshot file : ", file_path );

        stream = new STREAM();
        stream.LoadFile( file_path );

        if ( stream.ReadSection( "Version" ) )
        {
            Version = stream.ReadNatural32();
        }

        if ( stream.ReadSection( "Time" ) )
        {
            Time = stream.ReadNatural64();
        }

        if ( stream.ReadSection( "DataFolderPath" ) )
        {
            DataFolderPath = stream.ReadText();
        }

        if ( stream.ReadSection( "FolderFilterArray" ) )
        {
            folder_filter_count = stream.ReadNatural32();

            for ( folder_filter_index = 0;
                  folder_filter_index < folder_filter_count;
                  ++folder_filter_index )
            {
                FolderFilterArray ~= stream.ReadText();
            }
        }

        if ( stream.ReadSection( "FolderFilterIsInclusiveArray" ) )
        {
            folder_filter_is_inclusive_count = stream.ReadNatural32();

            for ( folder_filter_is_inclusive_index = 0;
                  folder_filter_is_inclusive_index < folder_filter_is_inclusive_count;
                  ++folder_filter_is_inclusive_index )
            {
                FolderFilterIsInclusiveArray ~= stream.ReadBoolean();
            }
        }

        if ( stream.ReadSection( "FileFilterArray" ) )
        {
            file_filter_count = stream.ReadNatural32();

            for ( file_filter_index = 0;
                  file_filter_index < file_filter_count;
                  ++file_filter_index )
            {
                FileFilterArray ~= stream.ReadText();
            }
        }

        if ( stream.ReadSection( "FileFilterIsInclusiveArray" ) )
        {
            file_filter_is_inclusive_count = stream.ReadNatural32();

            for ( file_filter_is_inclusive_index = 0;
                  file_filter_is_inclusive_index < file_filter_is_inclusive_count;
                  ++file_filter_is_inclusive_index )
            {
                FileFilterIsInclusiveArray ~= stream.ReadBoolean();
            }
        }

        if ( stream.ReadSection( "SelectedFileFilterArray" ) )
        {
            selected_file_filter_count = stream.ReadNatural32();

            for ( selected_file_filter_index = 0;
                  selected_file_filter_index < selected_file_filter_count;
                  ++selected_file_filter_index )
            {
                SelectedFileFilterArray ~= stream.ReadText();
            }
        }

        if ( stream.ReadSection( "FolderArray" ) )
        {
            folder_count = stream.ReadNatural32();

            for ( folder_index = 0;
                  folder_index < folder_count;
                  ++folder_index )
            {
                snapshot_folder = new SNAPSHOT_FOLDER();
                snapshot_folder.Read( stream );

                if ( snapshot_folder.SuperFolderIndex == NoFolderIndex )
                {
                    snapshot_folder.Path = "";
                }
                else
                {
                    snapshot_folder.Path = FolderArray[ snapshot_folder.SuperFolderIndex ].Path ~ snapshot_folder.Name ~ "/";
                }

                FolderArray ~= snapshot_folder;
                FolderMap[ snapshot_folder.Path ] = snapshot_folder;
            }
        }

        if ( stream.ReadSection( "FileArray" ) )
        {
            file_count = stream.ReadNatural32();

            for ( file_index = 0;
                  file_index < file_count;
                  ++file_index )
            {
                snapshot_file = new SNAPSHOT_FILE();
                snapshot_file.Read( stream );

                snapshot_file.Folder = FolderArray[ snapshot_file.FolderIndex ];
                snapshot_file.Folder.FileArray ~= snapshot_file;
                snapshot_file.Folder.FileMap[ snapshot_file.Name ] = snapshot_file;

                FileArray ~= snapshot_file;
            }
        }

        assert( stream.IsRead() );
    }
}

// ~~

class ARCHIVE
{
    // -- ATTRIBUTES

    string
        Name;
    string
        FolderPath;
    string[]
        SnapshotNameArray;

    // -- CONSTRUCTORS

    this(
        string name
        )
    {
        Name = name;
        FolderPath = RepositoryFolderPath ~ "SNAPSHOT/" ~ name ~ "/";

        if ( !FolderPath.exists() )
        {
            FolderPath.AddFolder( true );
        }
    }

    // -- INQUIRIES

    bool HasSnapshotName(
        string snapshot_name
        )
    {
        return SnapshotNameArray.countUntil( snapshot_name ) >= 0;
    }

    // ~~

    string GetLastSnapshotName(
        )
    {
        if ( SnapshotNameArray.length > 0 )
        {
            return SnapshotNameArray[ $ - 1 ];
        }
        else
        {
            Abort( "No snapshot for archive : " ~ ArchiveName );

            return "";
        }
    }

    // ~~

    string GetSnapshotName(
        )
    {
        string
            snapshot_name;

        if ( SnapshotName == "" )
        {
            snapshot_name = GetLastSnapshotName();
        }
        else
        {
            snapshot_name = SnapshotName;
        }

        if ( HasSnapshotName( snapshot_name ) )
        {
            return snapshot_name;
        }
        else
        {
            Abort( "Snapshot not found : " ~ snapshot_name );

            return "";
        }
    }

    // ~~

    SNAPSHOT GetSnapshot(
        string snapshot_name
        )
    {
        SNAPSHOT
            snapshot;

        snapshot = new SNAPSHOT();
        snapshot.LoadFile( FolderPath ~ snapshot_name ~ ".dbs" );

        return snapshot;
    }

    // ~~

    SNAPSHOT GetLastSnapshot(
        )
    {
        if ( SnapshotNameArray.length > 0 )
        {
            return GetSnapshot( SnapshotNameArray[ $ - 1 ] );
        }
        else
        {
            return null;
        }
    }

    // ~~

    SNAPSHOT GetSnapshot(
        )
    {
        return GetSnapshot( GetSnapshotName() );
    }

    // ~~

    void SaveSnapshot(
        SNAPSHOT snapshot
        )
    {
        snapshot.SaveFile( FolderPath ~ snapshot.GetFileName() );
    }
}

// ~~

class HISTORY
{
    // -- ATTRIBUTES

    string
        FolderPath;
    ARCHIVE[ string ]
        ArchiveMap;

    // -- CONSTRUCTORS

    this(
        )
    {
        string
            archive_folder_path;

        FolderPath = RepositoryFolderPath ~ "SNAPSHOT/";

        if ( !FolderPath.exists() )
        {
            if ( BackupOptionIsEnabled )
            {
                FolderPath.AddFolder( true );
            }
            else
            {
                Abort( "Missing history folder : " ~ FolderPath );
            }
        }

        archive_folder_path = FolderPath ~ ArchiveName ~ "/";

        if ( !archive_folder_path.exists() )
        {
            if ( BackupOptionIsEnabled )
            {
                archive_folder_path.AddFolder( true );
            }
            else
            {
                Abort( "Missing archive folder : " ~ FolderPath );
            }
        }
    }

    // -- INQUIRIES


    ARCHIVE GetArchive(
        )
    {
        ARCHIVE *
            archive;

        archive = ArchiveName in ArchiveMap;

        if ( archive != null )
        {
            return *archive;
        }
        else
        {
            Abort( "Archive not found : " ~ ArchiveName );

            return null;
        }
    }

    // ~~

    string GetSnapshotName(
        string file_path
        )
    {
        return file_path.GetFileName()[ 0 .. $ - 4 ];
    }

    // -- OPERATIONS

    void Scan(
        )
    {
        string
            archive_name,
            file_path,
            folder_path;
        ARCHIVE
            archive;

        writeln( "Scanning history folder : ", FolderPath );

        foreach ( archive_folder_entry; dirEntries( FolderPath, SpanMode.shallow ) )
        {
            if ( archive_folder_entry.isDir )
            {
                folder_path = archive_folder_entry.name.GetLogicalPath();
                archive_name = folder_path.GetFileName();
                archive = new ARCHIVE( archive_name );

                ArchiveMap[ archive_name ] = archive;

                foreach ( snapshot_folder_entry; dirEntries( archive_folder_entry, SpanMode.shallow ) )
                {
                    file_path = snapshot_folder_entry.name.GetLogicalPath();

                    if ( file_path.endsWith( ".dbs" ) )
                    {
                        archive.SnapshotNameArray ~= GetSnapshotName( file_path );
                    }
                }

                archive.SnapshotNameArray.sort();
            }
        }
    }
}

// ~~

class STORE
{
    // -- ATTRIBUTES

    string
        FolderPath;
    bool[ string ]
        HasFilePathMap;

    // -- CONSTRUCTORS

    this(
        )
    {
        FolderPath = RepositoryFolderPath ~ "FILE/";

        if ( !FolderPath.exists() )
        {
            if ( BackupOptionIsEnabled )
            {
                FolderPath.AddFolder( true );
            }
            else
            {
                Abort( "Missing store folder : " ~ FolderPath );
            }
        }
    }

    // -- INQUIRIES

    bool HasFilePath(
        string file_path
        )
    {
        return ( file_path in HasFilePathMap ) != null;
    }

    // ~~

    bool IsValidFilePath(
        string file_path,
        ulong byte_count
        )
    {
        string
            file_name,
            hexadecimal_byte_count;

        file_name = file_path.GetFileName().split( '.' )[ 0 ];

        if ( file_name.length > 65 )
        {
            hexadecimal_byte_count = file_name[ 65 .. $ ];

            return parse!long( hexadecimal_byte_count, 16 ) == byte_count;
        }
        else
        {
            return false;
        }
    }


    // -- OPERATIONS

    void Scan(
        )
    {
        string
            file_path;

        if ( FolderPath.exists() )
        {
            writeln( "Scanning store folder : ", FolderPath );

            try
            {
                foreach ( folder_entry; dirEntries( FolderPath, SpanMode.breadth ) )
                {
                    file_path = folder_entry.name.GetLogicalPath()[ FolderPath.length .. $ ];

                    if ( file_path.endsWith( ".dbf" ) )
                    {
                        if ( IsValidFilePath( file_path, folder_entry.size ) )
                        {
                            HasFilePathMap[ file_path ] = true;
                        }
                        else
                        {
                            writeln( "Invalid store file : ", file_path );
                        }
                    }
                }
            }
            catch ( Exception exception )
            {
                Abort( "Can't scan store folder : " ~ FolderPath, exception );
            }
        }
        else
        {
            writeln( "Creating store folder : ", FolderPath );

            FolderPath.AddFolder( true );
        }
    }

    // ~~

    void BackupDataFile(
        SNAPSHOT_FILE data_snapshot_file
        )
    {
        string
            data_file_path,
            store_file_path,
            store_folder_path;
        uint
            attribute_mask;
        SysTime
            access_time,
            modification_time;

        data_file_path = DataFolderPath ~ data_snapshot_file.GetFilePath();
        data_snapshot_file.HashDataFile( data_file_path );
        store_file_path = data_snapshot_file.GetStoreFilePath();

        writeln( "Backuping data file : ", data_file_path );

        store_file_path = FolderPath ~ store_file_path;
        store_folder_path = store_file_path.GetFolderPath();

        if ( !store_folder_path.exists() )
        {
            store_folder_path.AddFolder();
        }

        if ( VerboseOptionIsEnabled )
        {
            writeln( "Writing store file : ", store_file_path );
        }

        if ( !HasFilePath( store_file_path ) )
        {
            try
            {
                data_file_path.copy( store_file_path, PreserveAttributes.no );
            }
            catch ( Exception exception )
            {
                Abort( "Can't backup data file : " ~ data_file_path ~ " => " ~ store_file_path, exception, false );
            }
        }
    }

    // ~~

    void BackupDataFolder(
        SNAPSHOT data_snapshot,
        SNAPSHOT archive_snapshot
        )
    {
        SNAPSHOT_FILE
            archive_snapshot_file;

        foreach ( data_snapshot_file; data_snapshot.FileArray )
        {
            if ( archive_snapshot !is null )
            {
                archive_snapshot_file = archive_snapshot.GetSameFile( data_snapshot_file );
            }
            else
            {
                archive_snapshot_file = null;
            }

            if ( archive_snapshot_file !is null )
            {
                data_snapshot_file.Hash = archive_snapshot_file.Hash;
            }
            else
            {
                BackupDataFile( data_snapshot_file );
            }
        }
    }

    // ~~

    void CheckDataFolder(
        SNAPSHOT data_snapshot,
        SNAPSHOT archive_snapshot
        )
    {
    }

    // ~~

    void CompareDataFolder(
        SNAPSHOT data_snapshot,
        SNAPSHOT archive_snapshot
        )
    {
        SNAPSHOT_FILE
            found_data_snapshot_file;

        foreach ( archive_snapshot_file; archive_snapshot.FileArray )
        {
            found_data_snapshot_file = data_snapshot.GetFile( archive_snapshot_file );

            if ( found_data_snapshot_file is null )
            {
                writeln( "Missing archive file : ", archive_snapshot_file.GetFilePath() );
            }
            else if ( !found_data_snapshot_file.IsSame( archive_snapshot_file ) )
            {
                writeln( "Changed archive file : ", archive_snapshot_file.GetFilePath() );
            }
        }

        foreach ( archive_snapshot_folder; archive_snapshot.FolderArray )
        {
            if ( !data_snapshot.HasFolder( archive_snapshot_folder ) )
            {
                writeln( "Missing archive folder : ", archive_snapshot_folder.Path );
            }
        }

        foreach ( data_snapshot_file; data_snapshot.FileArray )
        {
            if ( !archive_snapshot.HasFile( data_snapshot_file ) )
            {
                writeln( "Missing data file : ", data_snapshot_file.GetFilePath() );
            }
        }

        foreach ( data_snapshot_folder; data_snapshot.FolderArray )
        {
            if ( !archive_snapshot.HasFolder( data_snapshot_folder ) )
            {
                writeln( "Missing data folder : ", data_snapshot_folder.Path );
            }
        }
    }

    // ~~

    void RemoveDataFolder(
        SNAPSHOT_FOLDER data_snapshot_folder
        )
    {
        string
            data_folder_path;

        data_folder_path = DataFolderPath ~ data_snapshot_folder.Path;

        if ( data_folder_path.IsEmptyFolder() )
        {
            data_folder_path.RemoveFolder( true );
        }
    }

    // ~~

    void RemoveDataFile(
        SNAPSHOT_FILE data_snapshot_file
        )
    {
        string
            data_file_path;

        data_file_path = DataFolderPath ~ data_snapshot_file.Folder.Path ~ data_snapshot_file.Name;
        data_file_path.RemoveFile( true );
    }

    // ~~

    void RemoveDataFiles(
        SNAPSHOT data_snapshot,
        SNAPSHOT archive_snapshot
        )
    {
        foreach ( data_snapshot_file; data_snapshot.FileArray )
        {
            if ( !archive_snapshot.HasFile( data_snapshot_file ) )
            {
                RemoveDataFile( data_snapshot_file );
            }
        }

        foreach ( data_snapshot_folder; data_snapshot.FolderArray )
        {
            if ( !archive_snapshot.HasFolder( data_snapshot_folder ) )
            {
                RemoveDataFolder( data_snapshot_folder );
            }
        }
    }

    // ~~

    void RestoreArchiveFile(
        SNAPSHOT_FILE archive_snapshot_file
        )
    {
        string
            data_file_path,
            data_folder_path,
            store_file_path;

        data_file_path = DataFolderPath ~ archive_snapshot_file.GetFilePath();
        store_file_path = FolderPath ~ archive_snapshot_file.GetStoreFilePath();

        data_folder_path = data_file_path.GetFolderPath();

        if ( !data_folder_path.exists() )
        {
            data_folder_path.AddFolder( true );
        }

        writeln( "Restoring data file : ", data_file_path );

        try
        {
            version ( Windows )
            {
                if ( data_file_path.exists() )
                {
                    data_file_path.setAttributes( archive_snapshot_file.AttributeMask & ~1 );
                }

                store_file_path.copy( data_file_path, PreserveAttributes.no );

                data_file_path.setAttributes( archive_snapshot_file.AttributeMask & ~1 );
                data_file_path.setTimes(
                    archive_snapshot_file.AccessTime.GetTime(),
                    archive_snapshot_file.ModificationTime.GetTime()
                    );
                data_file_path.setAttributes( archive_snapshot_file.AttributeMask );
            }
            else
            {
                if ( data_file_path.exists() )
                {
                    data_file_path.setAttributes( 511 );
                }

                store_file_path.copy( data_file_path, PreserveAttributes.no );

                data_file_path.setAttributes( archive_snapshot_file.AttributeMask );
                data_file_path.setTimes(
                    archive_snapshot_file.AccessTime.GetTime(),
                    archive_snapshot_file.ModificationTime.GetTime()
                    );
            }
        }
        catch ( Exception exception )
        {
            Abort( "Can't restore file : " ~ store_file_path ~ " => " ~ data_file_path, exception, false );
        }
    }

    // ~~

    void RestoreDataFolder(
        SNAPSHOT data_snapshot,
        SNAPSHOT archive_snapshot
        )
    {
        SNAPSHOT_FILE
            data_snapshot_file;

        foreach ( archive_snapshot_file; archive_snapshot.FileArray )
        {
            data_snapshot_file = data_snapshot.GetSameFile( archive_snapshot_file );

            if ( data_snapshot_file is null )
            {
                RestoreArchiveFile( archive_snapshot_file );
            }
        }

        RemoveDataFiles( data_snapshot, archive_snapshot );
    }
}

// ~~

class REPOSITORY
{
    // -- ATTRIBUTES

    string
        FolderPath;
    HISTORY
        History;
    STORE
        Store;

    // -- CONSTRUCTORS

    this(
        )
    {
        FolderPath = RepositoryFolderPath;

        if ( !FolderPath.exists() )
        {
            if ( BackupOptionIsEnabled )
            {
                FolderPath.AddFolder( true );
            }
            else
            {
                Abort( "Missing repository folder : " ~ FolderPath );
            }
        }

        History = new HISTORY();
        Store = new STORE();
        Scan();
    }

    // -- OPERATIONS

    void Scan(
        )
    {
        History.Scan();
        Store.Scan();
    }

    // ~~

    SNAPSHOT GetDataSnapshot(
        )
    {
        SNAPSHOT
            snapshot;

        writeln( "Scanning data folder : ", DataFolderPath );

        snapshot = new SNAPSHOT();
        snapshot.ScanDataFolder();

        return snapshot;
    }

    // ~~

    void BackupDataFolder(
        )
    {
        ARCHIVE
            archive;
        SNAPSHOT
            archive_snapshot,
            data_snapshot;

        data_snapshot = GetDataSnapshot();
        archive = History.GetArchive();
        archive_snapshot = archive.GetLastSnapshot();
        Store.BackupDataFolder( data_snapshot, archive_snapshot );
        archive.SaveSnapshot( data_snapshot );
    }

    // ~~

    void CheckDataFolder(
        )
    {
        ARCHIVE
            archive;
        SNAPSHOT
            archive_snapshot,
            data_snapshot;

        data_snapshot = GetDataSnapshot();
        archive = History.GetArchive();
        archive_snapshot = archive.GetSnapshot();
        Store.CheckDataFolder( data_snapshot, archive_snapshot );
    }

    // ~~

    void CompareDataFolder(
        )
    {
        ARCHIVE
            archive;
        SNAPSHOT
            archive_snapshot,
            data_snapshot;

        data_snapshot = GetDataSnapshot();
        archive = History.GetArchive();
        archive_snapshot = archive.GetSnapshot();
        Store.CompareDataFolder( data_snapshot, archive_snapshot );
    }

    // ~~

    void RestoreDataFolder(
        )
    {
        ARCHIVE
            archive;
        SNAPSHOT
            archive_snapshot,
            data_snapshot;

        data_snapshot = GetDataSnapshot();
        archive = History.GetArchive();
        archive_snapshot = archive.GetSnapshot();
        Store.RestoreDataFolder( data_snapshot, archive_snapshot );
    }

    // ~~

    void Find(
        )
    {
        string
            file_path;
        SNAPSHOT
            archive_snapshot;

        foreach ( archive_name, archive; History.ArchiveMap )
        {
            if ( archive_name.globMatch( ArchiveFilter ) )
            {
                writeln( "Reading archive folder : ", archive.FolderPath );

                foreach ( snapshot_name; archive.SnapshotNameArray )
                {
                    if ( SnapshotFilter == ""
                         || snapshot_name.globMatch( SnapshotFilter ) )
                    {
                        archive_snapshot = archive.GetSnapshot( snapshot_name );

                        foreach ( folder; archive_snapshot.FolderArray )
                        {
                            if ( IsIncludedFolder( "/" ~ folder.Path ) )
                            {
                                foreach ( file; folder.FileArray )
                                {
                                    file_path = file.GetFilePath();

                                    if ( IsIncludedFile( "/" ~ folder.Path, "/" ~ file_path, file.Name )
                                         && IsSelectedFile( "/" ~ folder.Path, "/" ~ file_path, file.Name ) )
                                    {
                                        writeln(
                                            "    ",
                                            file.GetStoreName(),
                                            " | ",
                                            file.ModificationTime.GetTimeStamp(),
                                            " | ",
                                            file_path,
                                            " | ",
                                            file.ByteCount
                                            );
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ~~

    void List(
        )
    {
        foreach ( archive_name, archive; History.ArchiveMap )
        {
            if ( archive_name.globMatch( ArchiveFilter ) )
            {
                writeln( "Archive : ", archive_name );

                foreach ( snapshot_name; archive.SnapshotNameArray )
                {
                    if ( snapshot_name.globMatch( SnapshotFilter ) )
                    {
                        writeln( "    Snapshot : ", snapshot_name );
                    }
                }
            }
        }
    }
}

// -- VARIABLES

bool
    AbortOptionIsEnabled,
    BackupOptionIsEnabled,
    CheckOptionIsEnabled,
    CompareOptionIsEnabled,
    FindOptionIsEnabled,
    ListOptionIsEnabled,
    RestoreOptionIsEnabled,
    VerboseOptionIsEnabled;
bool[]
    FileFilterIsInclusiveArray,
    FolderFilterIsInclusiveArray;
string
    ArchiveFilter,
    ArchiveName,
    DataFolderPath,
    RepositoryFolderPath,
    SnapshotFilter,
    SnapshotName;
string[]
    ErrorMessageArray,
    FileFilterArray,
    FolderFilterArray,
    SelectedFileFilterArray;
Duration
    NegativeAllowedOffsetDuration,
    PositiveAllowedOffsetDuration;

// -- FUNCTIONS

void PrintError(
    string message
    )
{
    writeln( "*** ERROR : ", message );

    ErrorMessageArray ~= message;
}

// ~~

void Abort(
    string message
    )
{
    PrintError( message );

    exit( -1 );
}

// ~~

void Abort(
    string message,
    Exception exception,
    bool it_must_exit = true
    )
{
    PrintError( message );
    PrintError( exception.msg );

    if ( it_must_exit
         || AbortOptionIsEnabled )
    {
        exit( -1 );
    }
}

// ~~

bool IsNatural(
    string text
    )
{
    if ( text.length == 0 )
    {
        return false;
    }
    else
    {
        foreach ( character; text )
        {
            if ( character < '0'
                 || character > '9' )
            {
                return false;
            }
        }

        return true;
    }
}

// ~~

bool IsIdentifier(
    string text
    )
{
    if ( text.length == 0 )
    {
        return false;
    }
    else
    {
        foreach ( character; text )
        {
            if ( !( ( character >= 'a' && character <= 'z' )
                    || ( character >= 'A' && character <= 'Z' )
                    || ( character >= '0' && character <= '9' )
                    || character == '_' ) )
            {
                return false;
            }
        }

        return true;
    }
}

// ~~

bool IsRootPath(
    string folder_path
    )
{
    return
        folder_path.startsWith( '/' )
        || folder_path.endsWith( '\\' );
}

// ~~

bool IsFolderPath(
    string folder_path
    )
{
    return
        folder_path.endsWith( '/' )
        || folder_path.endsWith( '\\' );
}

// ~~

bool IsFilter(
    string folder_path
    )
{
    return
        folder_path.indexOf( '*' ) >= 0
        || folder_path.indexOf( '?' ) >= 0;
}

// ~~

string GetLogicalPath(
    string path
    )
{
    return path.replace( '\\', '/' );
}

// ~~

string GetFolderPath(
    string file_path
    )
{
    long
        slash_character_index;

    slash_character_index = file_path.lastIndexOf( '/' );

    if ( slash_character_index >= 0 )
    {
        return file_path[ 0 .. slash_character_index + 1 ];
    }
    else
    {
        return "";
    }
}

// ~~

string GetFileName(
    string file_path
    )
{
    long
        slash_character_index;

    slash_character_index = file_path.lastIndexOf( '/' );

    if ( slash_character_index >= 0 )
    {
        return file_path[ slash_character_index + 1 .. $ ];
    }
    else
    {
        return file_path;
    }
}

// ~~

string GetFolderName(
    string folder_path
    )
{
    if ( folder_path.endsWith( '/' ) )
    {
        folder_path = folder_path[ 0 .. $ - 1 ];
    }

    return folder_path.GetFileName();
}

// ~~

bool IsIncludedFolder(
    string folder_path
    )
{
    bool
        folder_filter_is_inclusive,
        folder_is_included;

    folder_is_included = true;

    if ( FolderFilterArray.length > 0 )
    {
        foreach ( folder_filter_index, folder_filter; FolderFilterArray )
        {
            folder_filter_is_inclusive = FolderFilterIsInclusiveArray[ folder_filter_index ];

            if ( folder_filter_is_inclusive )
            {
                if ( folder_path.startsWith( folder_filter )
                     || folder_filter.startsWith( folder_path ) )
                {
                    folder_is_included = true;
                }
            }
            else
            {
                if ( !folder_filter.startsWith( '/' )
                     && !folder_filter.startsWith( '*' ) )
                {
                    folder_filter = "*/" ~ folder_filter;
                }

                if ( folder_path.globMatch( folder_filter ~ '*' ) )
                {
                    folder_is_included = false;
                }
            }
        }
    }

    return folder_is_included;
}

// ~~

bool IsIncludedFile(
    string folder_path,
    string file_path,
    string file_name
    )
{
    bool
        file_filter_is_inclusive,
        file_is_included;
    string
        file_name_filter,
        folder_path_filter;

    file_is_included = true;

    if ( FileFilterArray.length > 0 )
    {
        foreach ( file_filter_index, file_filter; FileFilterArray )
        {
            file_filter_is_inclusive = FileFilterIsInclusiveArray[ file_filter_index ];

            if ( !file_filter.startsWith( '/' )
                 && !file_filter.startsWith( '*' ) )
            {
                file_filter = "*/" ~ file_filter;
            }

            if ( file_filter.endsWith( '/' ) )
            {
                if ( folder_path.globMatch( file_filter ~ '*' ) )
                {
                    file_is_included = file_filter_is_inclusive;
                }
            }
            else if ( file_filter.indexOf( '/' ) >= 0 )
            {
                folder_path_filter = file_filter.GetFolderPath();
                file_name_filter = file_filter.GetFileName();

                if ( folder_path.globMatch( folder_path_filter )
                     && file_name.globMatch( file_name_filter ) )
                {
                    file_is_included = file_filter_is_inclusive;
                }
            }
            else
            {
                if ( file_name.globMatch( file_filter ) )
                {
                    file_is_included = file_filter_is_inclusive;
                }
            }
        }
    }

    return file_is_included;
}

// ~~

bool IsSelectedFile(
    string folder_path,
    string file_path,
    string file_name
    )
{
    bool
        file_is_selected;
    long
        selected_file_filter_index;
    string
        file_name_filter,
        folder_path_filter,
        selected_file_filter;

    file_is_selected = ( SelectedFileFilterArray.length == 0 );

    for ( selected_file_filter_index = 0;
          selected_file_filter_index < SelectedFileFilterArray.length
          && !file_is_selected;
          ++selected_file_filter_index )
    {
        selected_file_filter = SelectedFileFilterArray[ selected_file_filter_index ];

        if ( !selected_file_filter.startsWith( '/' )
             && !selected_file_filter.startsWith( '*' ) )
        {
            selected_file_filter = "*/" ~ selected_file_filter;
        }

        if ( selected_file_filter.endsWith( '/' ) )
        {
            if ( folder_path.globMatch( selected_file_filter ~ '*' ) )
            {
                file_is_selected = true;
            }
        }
        else if ( selected_file_filter.indexOf( '/' ) >= 0 )
        {
            folder_path_filter = selected_file_filter.GetFolderPath();
            file_name_filter = selected_file_filter.GetFileName();

            if ( folder_path.globMatch( folder_path_filter )
                 && file_name.globMatch( file_name_filter ) )
            {
                file_is_selected = true;
            }
        }
        else
        {
            if ( file_name.globMatch( selected_file_filter ) )
            {
                file_is_selected = true;
            }
        }
    }

    return file_is_selected;
}

// ~~

bool IsEmptyFolder(
    string folder_path
    )
{
    bool
        it_is_empty_folder;

    try
    {
        it_is_empty_folder = true;

        foreach ( folder_entry; dirEntries( folder_path, SpanMode.shallow ) )
        {
            it_is_empty_folder = false;

            break;
        }
    }
    catch ( Exception exception )
    {
        Abort( "Can't read folder : " ~ folder_path, exception );
    }

    return it_is_empty_folder;
}

// ~~

void AddFolder(
    string folder_path,
    bool it_is_verbose = false
    )
{
    if ( it_is_verbose )
    {
        writeln( "Adding folder : ", folder_path );
    }

    try
    {
        if ( folder_path != ""
             && folder_path != "/"
             && !folder_path.exists() )
        {
            folder_path.mkdirRecurse();
        }
    }
    catch ( Exception exception )
    {
        Abort( "Can't add folder : " ~ folder_path, exception );
    }
}

// ~~

void RemoveFolder(
    string folder_path,
    bool it_is_verbose = false
    )
{
    if ( it_is_verbose )
    {
        writeln( "Removing folder : ", folder_path );
    }

    try
    {
        folder_path.rmdir();
    }
    catch ( Exception exception )
    {
        Abort( "Can't remove folder : " ~ folder_path, exception );
    }
}

// ~~

ubyte[] ReadByteArray(
    string file_path,
    bool it_is_verbose = false
    )
{
    ubyte[]
        file_byte_array;

    if ( it_is_verbose )
    {
        writeln( "Reading file : ", file_path );
    }

    try
    {
        file_byte_array = cast( ubyte[] )file_path.read();
    }
    catch ( Exception exception )
    {
        Abort( "Can't read file : " ~ file_path, exception );
    }

    return file_byte_array;
}

// ~~

void WriteByteArray(
    string file_path,
    ubyte[] file_byte_array,
    bool it_is_verbose = false
    )
{
    if ( it_is_verbose )
    {
        writeln( "Writing file : ", file_path );
    }

    try
    {
        file_path.write( file_byte_array );
    }
    catch ( Exception exception )
    {
        Abort( "Can't write file : " ~ file_path, exception );
    }
}

// ~~

string ReadText(
    string file_path,
    bool it_is_verbose = false
    )
{
    string
        file_text;

    if ( it_is_verbose )
    {
        writeln( "Reading file : ", file_path );
    }

    try
    {
        file_text = file_path.readText();
    }
    catch ( Exception exception )
    {
        Abort( "Can't read file : " ~ file_path, exception );
    }

    return file_text;
}

// ~~

void WriteText(
    string file_path,
    string file_text,
    bool it_is_verbose = false
    )
{
    if ( it_is_verbose )
    {
        writeln( "Writing file : ", file_path );
    }

    try
    {
        file_path.write( file_text );
    }
    catch ( Exception exception )
    {
        Abort( "Can't write file : " ~ file_path, exception );
    }
}

// ~~

void RemoveFile(
    string file_path,
    bool it_is_verbose = false
    )
{
    if ( it_is_verbose )
    {
        writeln( "Removing file : ", file_path );
    }

    try
    {
        file_path.remove();
    }
    catch ( Exception exception )
    {
        Abort( "Can't remove file : " ~ file_path, exception );
    }
}

// ~~

ulong GetTime(
    SysTime system_time
    )
{
    return system_time.stdTime();
}

// ~~

SysTime GetTime(
    ulong time
    )
{
    return SysTime( time, UTC() );
}

// ~~

string GetTimeStamp(
    ulong time
    )
{
    string
        time_stamp;

    time_stamp = ( time.GetTime().toISOString().replace( "T", "" ).replace( "Z", "" ).replace( ".", "" ) ~ "0000000" )[ 0 .. 21 ];

    return
        time_stamp[ 0 .. 8 ]
        ~ "_"
        ~ time_stamp[ 8 .. 14 ]
        ~ "_"
        ~ time_stamp[ 14 .. $ ];
}

// ~~

string GetRelativePath(
    string path
    )
{
    return path[ DataFolderPath.length .. $ ];
}

// ~~

void main(
    string[] argument_array
    )
{
    bool
        it_has_command;
    long
        millisecond_count;
    string
        option;
    REPOSITORY
        repository;

    argument_array = argument_array[ 1 .. $ ];

    ErrorMessageArray = null;
    DataFolderPath = "";
    RepositoryFolderPath = "";
    ArchiveName = "DEFAULT";
    ArchiveFilter = "*";
    SnapshotName = "";
    SnapshotFilter = "*";
    BackupOptionIsEnabled = false;
    CheckOptionIsEnabled = false;
    CompareOptionIsEnabled = false;
    RestoreOptionIsEnabled = false;
    FindOptionIsEnabled = false;
    ListOptionIsEnabled = false;
    FolderFilterArray = null;
    FolderFilterIsInclusiveArray = null;
    FileFilterArray = null;
    FileFilterIsInclusiveArray = null;
    NegativeAllowedOffsetDuration = msecs( 1 );
    PositiveAllowedOffsetDuration = msecs( 1 );
    AbortOptionIsEnabled = false;
    VerboseOptionIsEnabled = false;

    while ( argument_array.length >= 1
            && argument_array[ 0 ].startsWith( "--" ) )
    {
        option = argument_array[ 0 ];

        argument_array = argument_array[ 1 .. $ ];

        if ( ( option == "--backup"
               || option == "--check"
               || option == "--compare"
               || option == "--restore" )
             && argument_array.length >= 2
             && argument_array[ 0 ].IsFolderPath()
             && argument_array[ 1 ].IsFolderPath()
             && argument_array[ 1 ] != argument_array[ 0 ]
             && !it_has_command )
        {
            BackupOptionIsEnabled = ( option == "--backup" );
            CheckOptionIsEnabled = ( option == "--check" );
            CompareOptionIsEnabled = ( option == "--compare" );
            RestoreOptionIsEnabled = ( option == "--restore" );

            DataFolderPath = argument_array[ 0 ].GetLogicalPath();
            RepositoryFolderPath = argument_array[ 1 ].GetLogicalPath();
            it_has_command = true;

            argument_array = argument_array[ 2 .. $ ];
        }
        else if ( option == "--find"
                  && argument_array.length >= 1
                  && argument_array[ 0 ].IsFolderPath()
                  && !it_has_command )
        {
            FindOptionIsEnabled = true;

            RepositoryFolderPath = argument_array[ 0 ].GetLogicalPath();
            it_has_command = true;

            argument_array = argument_array[ 1 .. $ ];
        }
        else if ( option == "--list"
                  && argument_array.length >= 1
                  && argument_array[ 0 ].IsFolderPath()
                  && !it_has_command )
        {
            ListOptionIsEnabled = true;

            RepositoryFolderPath = argument_array[ 0 ].GetLogicalPath();

            argument_array = argument_array[ 1 .. $ ];
        }
        else if ( option == "--exclude"
                  && argument_array.length >= 1
                  && argument_array[ 0 ].IsFolderPath() )
        {
            FolderFilterArray ~= argument_array[ 0 ].GetLogicalPath();
            FolderFilterIsInclusiveArray ~= false;

            argument_array = argument_array[ 1 .. $ ];
        }
        else if ( option == "--include"
                  && argument_array.length >= 1
                  && argument_array[ 0 ].IsRootPath()
                  && argument_array[ 0 ].IsFolderPath()
                  && !argument_array[ 0 ].IsFilter() )
        {
            FolderFilterArray ~= argument_array[ 0 ].GetLogicalPath();
            FolderFilterIsInclusiveArray ~= true;

            argument_array = argument_array[ 1 .. $ ];
        }
        else if ( ( option == "--ignore"
                    || option == "--keep" )
                  && argument_array.length >= 1 )
        {
            FileFilterArray ~= argument_array[ 0 ].GetLogicalPath();
            FileFilterIsInclusiveArray ~= ( option == "--keep" );

            argument_array = argument_array[ 1 .. $ ];
        }
        else if ( option == "--select"
                  && argument_array.length >= 1 )
        {
            SelectedFileFilterArray ~= argument_array[ 0 ].GetLogicalPath();

            argument_array = argument_array[ 1 .. $ ];
        }
        else if ( option == "--precision"
                  && argument_array.length >= 1
                  && argument_array[ 2 ].IsNatural() )
        {
            millisecond_count = argument_array[ 0 ].to!long();

            NegativeAllowedOffsetDuration = msecs( -millisecond_count );
            PositiveAllowedOffsetDuration = msecs( millisecond_count );

            argument_array = argument_array[ 1 .. $ ];
        }
        else if ( option == "--abort" )
        {
            AbortOptionIsEnabled = true;
        }
        else if ( option == "--verbose" )
        {
            VerboseOptionIsEnabled = true;
        }
        else
        {
            Abort( "Invalid option : " ~ option );
        }

        if ( ( option == "--backup"
               || option == "--check"
               || option == "--compare"
               || option == "--restore" )
             && argument_array.length >= 1
             && argument_array[ 0 ].IsIdentifier() )
        {
            ArchiveName = argument_array[ 0 ];

            argument_array = argument_array[ 1 .. $ ];
        }

        if ( ( option == "--find"
               || option == "--list" )
             && argument_array.length >= 1
             && !argument_array[ 0 ].startsWith( "--" ) )
        {
            ArchiveFilter = argument_array[ 0 ];

            argument_array = argument_array[ 1 .. $ ];
        }

        if ( ( option == "--check"
               || option == "--compare"
               || option == "--restore" )
             && argument_array.length >= 1
             && argument_array[ 0 ].IsIdentifier() )
        {
            SnapshotName = argument_array[ 0 ];

            argument_array = argument_array[ 1 .. $ ];
        }

        if ( ( option == "--find"
               || option == "--list" )
             && argument_array.length >= 1
             && !argument_array[ 0 ].startsWith( "--" ) )
        {
            SnapshotFilter = argument_array[ 0 ];

            argument_array = argument_array[ 1 .. $ ];
        }
    }

    if ( argument_array.length == 0
         && ( BackupOptionIsEnabled
              || CheckOptionIsEnabled
              || CompareOptionIsEnabled
              || RestoreOptionIsEnabled
              || FindOptionIsEnabled
              || ListOptionIsEnabled ) )
    {
        repository = new REPOSITORY();

        if ( BackupOptionIsEnabled )
        {
            repository.BackupDataFolder();
        }
        else if ( CheckOptionIsEnabled )
        {
            repository.CheckDataFolder();
        }
        else if ( CompareOptionIsEnabled )
        {
            repository.CompareDataFolder();
        }
        else if ( RestoreOptionIsEnabled )
        {
            repository.RestoreDataFolder();
        }
        else if ( FindOptionIsEnabled )
        {
            repository.Find();
        }
        else if ( ListOptionIsEnabled )
        {
            repository.List();
        }
    }
    else
    {
        writeln( "Usage :" );
        writeln( "    dub [options] DATA_FOLDER/ REPOSITORY_FOLDER/" );
        writeln( "Options :" );
        writeln( "Examples :" );
        writeln( "    dub --backup DATA_FOLDER/ REPOSITORY_FOLDER/ archive_name" );

        Abort( "Invalid arguments : " ~ argument_array.to!string() );
    }
}
