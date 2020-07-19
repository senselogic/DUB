![](https://github.com/senselogic/DUB/blob/master/LOGO/dub.png)

# Dub

Deduplicated backup tool.

## Installation

Install the [DMD 2 compiler](https://dlang.org/download.html) (using the MinGW setup option on Windows).

Build the executable with the following command line :

```bash
dmd -m64 dub.d
```

## Command line

```bash
dub [options]
```

### Options

```
--backup DATA_FOLDER/ REPOSITORY_FOLDER/ : backup the data files into the default archive
--backup DATA_FOLDER/ REPOSITORY_FOLDER/ archive_name : backup the data files into this archive
--check DATA_FOLDER/ REPOSITORY_FOLDER/ : check the latest snapshot of the default archive
--check DATA_FOLDER/ REPOSITORY_FOLDER/ archive_name : check the latest snapshot of this archive
--check DATA_FOLDER/ REPOSITORY_FOLDER/ archive_name snapshot_name : check a snapshot of this archive
--compare DATA_FOLDER/ REPOSITORY_FOLDER/ : compare the data files to the default archive
--compare DATA_FOLDER/ REPOSITORY_FOLDER/ archive_name : compare the data files to the latest snapshot of this archive
--compare DATA_FOLDER/ REPOSITORY_FOLDER/ archive_name snapshot_name : compare the data files to a snapshot of this archive
--restore DATA_FOLDER/ REPOSITORY_FOLDER/ : restore the data files from the default archive
--restore DATA_FOLDER/ REPOSITORY_FOLDER/ archive_name : restore the data files from the latest snapshot of this archive
--restore DATA_FOLDER/ REPOSITORY_FOLDER/ archive_name snapshot_name : restore the data files from a snapshot of this archive
--find REPOSITORY_FOLDER/ : find matching files in the snapshots of the default archive
--find REPOSITORY_FOLDER/ archive_name : find matching files in the snapshots of this archive
--find REPOSITORY_FOLDER/ archive_name snapshot_name : find matching files in a snapshot of this archive
--list REPOSITORY_FOLDER/ : list the snapshots of the default archive
--list REPOSITORY_FOLDER/ archive_name : list the snapshots of this archive
--exclude FOLDER_FILTER/ : exclude matching folders
--include FOLDER/ : include this folder
--ignore file_filter : ignore matching files
--keep file_filter : keep matching files
--select file_filter : exclusively select matching files
--abort : abort on errors
--verbose : show the processing messages
```

### Examples

```bash
dub --backup DATA_FOLDER/ REPOSITORY_FOLDER/
```

Backups the data files into the default archive of this repository.

```bash
dub --backup DATA_FOLDER/ REPOSITORY_FOLDER/ MONDAY --excude "/TEMP/"
```

Backups the data files into the `MONDAY` archive of this repository, excluding the `TEMP` root folder.

```bash
dub --check DATA_FOLDER/ REPOSITORY_FOLDER MONDAY
```

Checks the latest snapshot of the `MONDAY` archive of this repository.

```bash
dub --compare REPOSITORY_FOLDER MONDAY
```

Compares the data files to the latest snapshot of the `MONDAY` archive of this repository.

```bash
dub --restore DATA_FOLDER/ REPOSITORY_FOLDER/ MONDAY
```

Restore the data files from the default archive.

```bash
dub --restore DATA_FOLDER/ REPOSITORY_FOLDER/ MONDAY 202007052054138436
```

Restore the data files from the `202007191717441348878` snapshot of the `MONDAY` archive of this repository.

```bash
dub --find REPOSITORY_FOLDER/ --select "/A/*.tmp"
```

Find matching files in the snapshots of the default archive of this repository.

```bash
dub --list REPOSITORY_FOLDER/
```

List the snapshots of the default archive of this repository.

## Limitations

* Symbolic links are not processed.
* Only local repositories are handled.
* Files are stored uncompressed and unencrypted, to allow external access.

## Version

0.1

## Author

Eric Pelzer (ecstatic.coder@gmail.com).

## License

This project is licensed under the GNU General Public License version 3.

See the [LICENSE.md](LICENSE.md) file for details.
