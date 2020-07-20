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
import std.conv : to;
import std.datetime : Clock, SysTime;
import std.digest : toHexString;
import std.digest.sha : SHA256;
import std.file : copy, dirEntries, exists, getAttributes, getTimes, mkdir, mkdirRecurse, read, readText, remove, rename, rmdir, setAttributes, setTimes, write, PreserveAttributes, SpanMode;
import std.format : format;
import std.path : globMatch;
import std.stdio : readln, writeln, File;
import std.string : endsWith, indexOf, join, lastIndexOf, replace, startsWith, toLower, toUpper;

// -- CONSTANTS

const uint
    NoFolderIndex = -1;

// -- TYPES

alias HASH = ubyte[ 32 ];

// ~~

union TIME
{
    // -- ATTRIBUTES

    SysTime
        SystemTime;
    ubyte[ 16 ]
        ByteArray;
}

// ~~

class STREAM
{
    // -- ATTRIBUTES

    ubyte[]
        ByteArray;
    ulong
        ByteIndex;
    ubyte[]
        SectionByteArray;

    // -- INQUIRIES

    bool IsRead(
        )
    {
        return ByteIndex == ByteArray.length;
    }

    // -- OPERATIONS

    void WriteByte(
        ubyte byte_
        )
    {
        SectionByteArray ~= byte_;
    }

    // ~~

    void WriteBoolean(
        bool boolean
        )
    {
        SectionByteArray ~= boolean ? 1 : 0;
    }

    // ~~

    void WriteNatural64(
        ulong natural
        )
    {
        while ( natural > 127 )
        {
            SectionByteArray ~= cast( ubyte )( 128 | ( natural & 127 ) );

            natural >>= 7;
        }

        SectionByteArray ~= cast( ubyte )( natural & 127 );
    }

    // ~~

    void WriteNatural32(
        uint natural
        )
    {
        WriteNatural64( natural );
    }

    // ~~

    void WriteNatural16(
        ushort natural
        )
    {
        WriteNatural64( natural );
    }

    // ~~

    void WriteSystemTime(
        SysTime system_time
        )
    {
        TIME
            time;

        time.SystemTime = system_time;
        SectionByteArray ~= time.ByteArray;

        assert( time.ByteArray.sizeof == time.SystemTime.sizeof );
    }

    // ~~

    void WriteText(
        string text
        )
    {
        WriteNatural64( text.length );
        SectionByteArray ~= cast( ubyte[] )text[ 0 .. $ ];
    }

    // ~~

    void WriteHash(
        HASH hash
        )
    {
        SectionByteArray ~= hash;
    }

    // ~~

    void WriteSection(
        string tag = ""
        )
    {
        ulong
            section_byte_count;

        if ( SectionByteArray.length > 0 )
        {
            section_byte_count = SectionByteArray.length;

            while ( section_byte_count > 127 )
            {
                ByteArray ~= cast( ubyte )( 128 | ( section_byte_count & 127 ) );

                section_byte_count >>= 7;
            }

            ByteArray ~= cast( ubyte )( section_byte_count & 127 );
            ByteArray ~= SectionByteArray;

            SectionByteArray.length = 0;
        }

        if ( tag != "" )
        {
            ByteArray ~= tag[ 0 ];
            ByteArray ~= tag[ 1 ];
            ByteArray ~= tag[ 2 ];
            ByteArray ~= tag[ 3 ];
        }
    }

    // ~~

    void Save(
        string file_path
        )
    {
        file_path.WriteByteArray( ByteArray );
    }

    // ~~

    ubyte ReadByte(
        )
    {
        return ByteArray[ ByteIndex++ ];
    }

    // ~~

    bool ReadBoolean(
        )
    {
        return ReadByte() != 0;
    }

    // ~~

    ulong ReadNatural64(
        )
    {
        uint
            bit_count;
        ulong
            natural,
            byte_;

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

    uint ReadNatural32(
        )
    {
        return cast( uint )ReadNatural64();
    }

    // ~~

    ushort ReadNatural16(
        )
    {
        return cast( ushort )ReadNatural64();
    }

    // ~~

    SysTime ReadSystemTime(
        )
    {
        TIME
            time;

        time.ByteArray = ByteArray[ ByteIndex .. ByteIndex + 16 ][ 0 .. 16 ];
        ByteIndex += 16;

        return time.SystemTime;
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

    HASH ReadHash(
        )
    {
        ByteIndex += 32;

        return ByteArray[ ByteIndex - 32 .. ByteIndex ][ 0 .. 32 ];
    }

    // ~~

    bool HasTag(
        string tag
        )
    {
        return
            ByteIndex + 4 <= ByteArray.length
            && ByteArray[ ByteIndex ] == tag[ 0 ]
            && ByteArray[ ByteIndex + 1 ] == tag[ 1 ]
            && ByteArray[ ByteIndex + 2 ] == tag[ 2 ]
            && ByteArray[ ByteIndex + 3 ] == tag[ 3 ];
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
            ByteIndex += 4;

            section_byte_count = ReadNatural64();

            return true;
        }
        else
        {
            writeln( "Section not found : ", tag, " (", ByteIndex, ")" );

            return false;
        }
    }

    // ~~

    void Load(
        string file_path
        )
    {
        ByteArray = file_path.ReadByteArray();
        ByteIndex = 0;
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
    SysTime
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
        stream.WriteSystemTime( AccessTime );
        stream.WriteSystemTime( ModificationTime );
        stream.WriteNatural32( AttributeMask );
    }

    // ~~

    void Read(
        STREAM stream
        )
    {
        SuperFolderIndex = stream.ReadNatural32();
        Name = stream.ReadText();
        AccessTime = stream.ReadSystemTime();
        ModificationTime = stream.ReadSystemTime();
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
        ByteCount;
    SysTime
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

    string GetStoreFileName(
        )
    {
        return cast( string )Hash.toHexString() ~ format( "%x", ByteCount ) ~ ".dbf";
    }

    // ~~

    string GetStoreFilePath(
        )
    {
        string
            store_file_name;

        store_file_name = GetStoreFileName();

        return store_file_name[ 0 .. 2 ] ~ "/" ~ store_file_name[ 2 .. 4 ] ~ "/" ~ store_file_name;
    }

    // -- OPERATIONS

    void Write(
        STREAM stream
        )
    {
        stream.WriteNatural32( FolderIndex );
        stream.WriteText( Name );
        stream.WriteHash( Hash );
        stream.WriteNatural64( ByteCount );
        stream.WriteSystemTime( AccessTime );
        stream.WriteSystemTime( ModificationTime );
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
        AccessTime = stream.ReadSystemTime();
        ModificationTime = stream.ReadSystemTime();
        AttributeMask = stream.ReadNatural32();
    }
}

// ~~

class SNAPSHOT
{
    // -- ATTRIBUTES

    uint
        Version;
    SysTime
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
        return ( Time.toISOString().replace( "T", "" ).replace( ".", "" ) ~ "0000000" )[ 0 .. 21 ] ~ ".dbs";
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

    bool HasFolder(
        SNAPSHOT_FOLDER snapshot_folder
        )
    {
        return GetFolder( snapshot_folder.Path ) !is null;
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
             && found_snapshot_file.ByteCount == snapshot_file.ByteCount
             && found_snapshot_file.ModificationTime == snapshot_file.ModificationTime )
        {
            return found_snapshot_file;
        }
        else
        {
            return null;
        }
    }

    // -- OPERATIONS

    void ReadFolder(
        string folder_path,
        SysTime folder_access_time,
        SysTime folder_modification_time,
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
                writeln( "Reading folder : ", DataFolderPath, relative_folder_path );
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
                        file_path = folder_entry.name;
                        file_name = file_path.GetFileName();
                        relative_file_path = GetRelativePath( folder_entry );

                        if ( IsIncludedFile( "/" ~ relative_folder_path, "/" ~ relative_file_path, file_name ) )
                        {
                            if ( VerboseOptionIsEnabled )
                            {
                                writeln( "Reading file : ", file_path );
                            }

                            snapshot_file = new SNAPSHOT_FILE();
                            snapshot_file.Folder = FolderArray[ folder_index ];
                            snapshot_file.FolderIndex = folder_index;
                            snapshot_file.Name = file_name;
                            snapshot_file.AccessTime = folder_entry.timeLastAccessed;
                            snapshot_file.ModificationTime = folder_entry.timeLastModified;
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
                        ReadFolder(
                            folder_entry.name ~ '/',
                            folder_entry.timeLastAccessed,
                            folder_entry.timeLastModified,
                            folder_entry.attributes,
                            folder_index
                            );
                    }
                }
            }
            catch ( Exception exception )
            {
                Abort( "Can't read folder : " ~ folder_path );
            }
        }
    }

    // ~~

    void ReadFolder(
        string folder_path
        )
    {
        uint
            attribute_mask;
        SysTime
            access_time,
            modification_time;

        if ( !folder_path.exists() )
        {
            folder_path.AddFolder();
        }

        attribute_mask = folder_path.getAttributes();
        folder_path.getTimes( access_time, modification_time );

        ReadFolder(
            folder_path,
            access_time,
            modification_time,
            attribute_mask,
            NoFolderIndex
            );
    }

    // ~~

    void ReadDataFolder(
        )
    {
        Version = 1;
        Time = Clock.currTime();
        DataFolderPath = .DataFolderPath;
        FolderFilterArray = .FolderFilterArray.dup();
        FolderFilterIsInclusiveArray = .FolderFilterIsInclusiveArray.dup();
        FileFilterArray = .FileFilterArray.dup();
        FileFilterIsInclusiveArray = .FileFilterIsInclusiveArray.dup();
        SelectedFileFilterArray = .SelectedFileFilterArray.dup();

        ReadFolder( DataFolderPath );
    }

    // ~~

    void Save(
        string file_path
        )
    {
        STREAM
            stream;

        stream = new STREAM();

        stream.WriteSection( "DUBS" );
        stream.WriteNatural32( Version );

        stream.WriteSection( "TIME" );
        stream.WriteSystemTime( Time );

        stream.WriteSection( "DATA" );
        stream.WriteText( DataFolderPath );

        stream.WriteSection( "FOLF" );
        stream.WriteNatural32( cast( uint )FolderFilterArray.length );

        foreach ( folder_filter; FolderFilterArray )
        {
            stream.WriteText( folder_filter );
        }

        stream.WriteSection( "FOLI" );
        stream.WriteNatural32( cast( uint )FolderFilterIsInclusiveArray.length );

        foreach ( folder_filter_is_inclusive; FolderFilterIsInclusiveArray )
        {
            stream.WriteBoolean( folder_filter_is_inclusive );
        }

        stream.WriteSection( "FILF" );
        stream.WriteNatural32( cast( uint )FileFilterArray.length );

        foreach ( file_filter; FileFilterArray )
        {
            stream.WriteText( file_filter );
        }

        stream.WriteSection( "FILI" );
        stream.WriteNatural32( cast( uint )FileFilterIsInclusiveArray.length );

        foreach ( file_filter_is_inclusive; FileFilterIsInclusiveArray )
        {
            stream.WriteBoolean( file_filter_is_inclusive );
        }

        stream.WriteSection( "SFIF" );
        stream.WriteNatural32( cast( uint )SelectedFileFilterArray.length );

        foreach ( selected_file_filter; SelectedFileFilterArray )
        {
            stream.WriteText( selected_file_filter );
        }

        stream.WriteSection( "FOLD" );
        stream.WriteNatural32( cast( uint )FolderArray.length );

        foreach ( snapshot_folder; FolderArray )
        {
            snapshot_folder.Write( stream );
        }

        stream.WriteSection( "FILE" );
        stream.WriteNatural32( cast( uint )FileArray.length );

        foreach ( snapshot_file; FileArray )
        {
            snapshot_file.Write( stream );
        }

        stream.WriteSection();
        stream.Save( file_path );
    }

    // ~~

    void Load(
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

        stream = new STREAM();
        stream.Load( file_path );

        if ( stream.ReadSection( "DUBS" ) )
        {
            Version = stream.ReadNatural32();
        }

        if ( stream.ReadSection( "TIME" ) )
        {
            Time = stream.ReadSystemTime();
        }

        if ( stream.ReadSection( "DATA" ) )
        {
            DataFolderPath = stream.ReadText();
        }

        if ( stream.ReadSection( "FOLF" ) )
        {
            folder_filter_count = stream.ReadNatural32();

            for ( folder_filter_index = 0;
                  folder_filter_index < folder_filter_count;
                  ++folder_filter_index )
            {
                FolderFilterArray ~= stream.ReadText();
            }
        }

        if ( stream.ReadSection( "FOLI" ) )
        {
            folder_filter_is_inclusive_count = stream.ReadNatural32();

            for ( folder_filter_is_inclusive_index = 0;
                  folder_filter_is_inclusive_index < folder_filter_is_inclusive_count;
                  ++folder_filter_is_inclusive_index )
            {
                FolderFilterIsInclusiveArray ~= stream.ReadBoolean();
            }
        }

        if ( stream.ReadSection( "FILF" ) )
        {
            file_filter_count = stream.ReadNatural32();

            for ( file_filter_index = 0;
                  file_filter_index < file_filter_count;
                  ++file_filter_index )
            {
                FileFilterArray ~= stream.ReadText();
            }
        }

        if ( stream.ReadSection( "FILI" ) )
        {
            file_filter_is_inclusive_count = stream.ReadNatural32();

            for ( file_filter_is_inclusive_index = 0;
                  file_filter_is_inclusive_index < file_filter_is_inclusive_count;
                  ++file_filter_is_inclusive_index )
            {
                FileFilterIsInclusiveArray ~= stream.ReadBoolean();
            }
        }

        if ( stream.ReadSection( "SFIF" ) )
        {
            selected_file_filter_count = stream.ReadNatural32();

            for ( selected_file_filter_index = 0;
                  selected_file_filter_index < selected_file_filter_count;
                  ++selected_file_filter_index )
            {
                SelectedFileFilterArray ~= stream.ReadText();
            }
        }

        if ( stream.ReadSection( "FOLD" ) )
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

        if ( stream.ReadSection( "FILE" ) )
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
            FolderPath.AddFolder();
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
        snapshot.Load( FolderPath ~ snapshot_name ~ ".dbs" );

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
        snapshot.Save( FolderPath ~ snapshot.GetFileName() );
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
        FolderPath = RepositoryFolderPath ~ "SNAPSHOT/";

        if ( !FolderPath.exists() )
        {
            FolderPath.AddFolder();
            ( FolderPath ~ "DEFAULT/" ).AddFolder();
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

    // -- OPERATIONS

    void Load(
        )
    {
        string
            archive_name,
            file_path,
            folder_path;
        ARCHIVE
            archive;

        writeln( "Reading history folder : ", FolderPath );

        foreach ( archive_folder_entry; dirEntries( FolderPath, SpanMode.shallow ) )
        {
            if ( archive_folder_entry.isDir )
            {
                folder_path = archive_folder_entry.name;
                archive_name = folder_path.GetFileName();
                archive = new ARCHIVE( archive_name );

                ArchiveMap[ archive_name ] = archive;

                foreach ( snapshot_folder_entry; dirEntries( archive_folder_entry, SpanMode.shallow ) )
                {
                    file_path = snapshot_folder_entry.name;

                    if ( file_path.endsWith( ".dbs" ) )
                    {
                        archive.SnapshotNameArray ~= file_path.GetFileName()[ 0 .. $ - 4 ];
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
            FolderPath.AddFolder();
        }
    }

    // -- INQUIRIES

    string GetFilePath(
        string file_name
        )
    {
        return
            FolderPath
            ~ file_name[ 0 .. 2 ]
            ~ "/"
            ~ file_name[ 2 .. 4 ]
            ~ "/"
            ~ file_name;
    }

    // ~~

    bool HasFilePath(
        string file_path
        )
    {
        return ( file_path in HasFilePathMap ) != null;
    }

    // -- OPERATIONS

    void AddFilePath(
        string file_path
        )
    {
        HasFilePathMap[ file_path ] = true;
    }

    // ~~

    void Load(
        )
    {
        string
            file_path;

        if ( FolderPath.exists() )
        {
            writeln( "Reading store folder : ", FolderPath );

            foreach ( folder_entry; dirEntries( FolderPath, SpanMode.breadth ) )
            {
                file_path = folder_entry.name[ FolderPath.length .. $ ];

                if ( file_path.endsWith( ".dbf" ) )
                {
                    AddFilePath( file_path );
                }
            }
        }
        else
        {
            writeln( "Creating store folder : ", FolderPath );

            FolderPath.AddFolder();
        }
    }

    // ~~

    void BackupFile(
        SNAPSHOT_FILE data_snapshot_file
        )
    {
        string
            data_file_path,
            store_file_path,
            store_folder_path;

        data_file_path = DataFolderPath ~ data_snapshot_file.GetFilePath();
        data_snapshot_file.Hash = data_file_path.GetFileHash();
        store_file_path = data_snapshot_file.GetStoreFilePath();

        if ( !HasFilePath( store_file_path ) )
        {
            writeln( "Backuping file : ", data_file_path );

            store_file_path = FolderPath ~ store_file_path;
            store_folder_path = store_file_path.GetFolderPath();

            if ( !store_folder_path.exists() )
            {
                store_folder_path.AddFolder();
            }

            writeln( "Writing file : ", store_file_path );

            data_file_path.copy( store_file_path, PreserveAttributes.no );
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

            if ( archive_snapshot_file is null )
            {
                BackupFile( data_snapshot_file );
            }
            else
            {
                data_snapshot_file.Hash = archive_snapshot_file.Hash;
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
            data_folder_path.RemoveFolder();
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
        data_file_path.RemoveFile();
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

        try
        {
            data_folder_path = data_file_path.GetFolderPath();

            writeln( "Restoring file : ", data_file_path );

            if ( !data_folder_path.exists() )
            {
                data_folder_path.AddFolder();
            }

            version ( Windows )
            {
                if ( data_file_path.exists() )
                {
                    data_file_path.setAttributes( archive_snapshot_file.AttributeMask & ~1 );
                }

                store_file_path.copy( data_file_path, PreserveAttributes.no );

                data_file_path.setAttributes( archive_snapshot_file.AttributeMask & ~1 );
                data_file_path.setTimes( archive_snapshot_file.AccessTime, archive_snapshot_file.ModificationTime );
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
                data_file_path.setTimes( archive_snapshot_file.AccessTime, archive_snapshot_file.ModificationTime );
            }
        }
        catch ( Exception exception )
        {
            Abort( "Can't restore file : " ~ store_file_path ~ " => " ~ data_file_path, exception, false );
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
        History = new HISTORY();
        Store = new STORE();
        Load();
    }

    // -- OPERATIONS

    void Load(
        )
    {
        History.Load();
        Store.Load();
    }

    // ~~

    SNAPSHOT GetDataSnapshot(
        )
    {
        SNAPSHOT
            snapshot;

        writeln( "Reading data folder : ", DataFolderPath );

        snapshot = new SNAPSHOT();
        snapshot.ReadDataFolder();

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
        ARCHIVE
            archive;
        SNAPSHOT
            archive_snapshot;

        archive = History.GetArchive();
        archive_snapshot = archive.GetSnapshot();
    }

    // ~~

    void List(
        )
    {
        // :TODO:
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
    ArchiveName,
    DataFolderPath,
    RepositoryFolderPath,
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
    return path.replace( "\\", "/" );
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
    string folder_path
    )
{
    writeln( "Adding folder : ", folder_path );

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
    string folder_path
    )
{
    writeln( "Removing folder : ", folder_path );

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
    string file_path
    )
{
    ubyte[]
        file_byte_array;

    writeln( "Reading file : ", file_path );

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
    ubyte[] file_byte_array
    )
{
    writeln( "Writing file : ", file_path );

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
    string file_path
    )
{
    string
        file_text;

    writeln( "Reading file : ", file_path );

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
    string file_text
    )
{
    writeln( "Writing file : ", file_path );

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
    string file_path
    )
{
    writeln( "Removing file : ", file_path );

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

HASH GetFileHash(
    string file_path
    )
{
    File
        file;
    HASH
        hash;
    SHA256
        sha256;

    writeln( "Hashing file : ", file_path );

    try
    {
        file = File( file_path );

        foreach ( byte_array; file.byChunk( 32 * 1024 * 1024 ) )
        {
            sha256.put( byte_array );
        }

        hash = sha256.finish();
    }
    catch ( Exception exception )
    {
        Abort( "Can't hash file : " ~ file_path, exception );
    }

    return hash;
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
    SnapshotName = "";
    ArchiveName = "DEFAULT";
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
               || option == "--restore"
               || option == "--find"
               || option == "--list" )
             && argument_array.length >= 1
             && argument_array[ 0 ].IsIdentifier() )
        {
            ArchiveName = argument_array[ 0 ];

            argument_array = argument_array[ 1 .. $ ];
        }

        if ( ( option == "--check"
               || option == "--compare"
               || option == "--restore"
               || option == "--find" )
             && argument_array.length >= 1
             && argument_array[ 0 ].IsIdentifier() )
        {
            SnapshotName = argument_array[ 0 ];

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
