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
--find REPOSITORY_FOLDER/ : find matching files in all snapshots
--find REPOSITORY_FOLDER/ archive_filter : find matching files in the snapshots of matching archives
--find REPOSITORY_FOLDER/ archive_filter snapshot_filter : find matching files in matching archive snapshots
--list REPOSITORY_FOLDER/ : list the snapshots of all snapshots
--list REPOSITORY_FOLDER/ archive_filter : list the snapshots of matching archives
--list REPOSITORY_FOLDER/ archive_filter snapshot_filter : list matching archive snapshots
--exclude FOLDER_FILTER/ : exclude matching folders
--include FOLDER/ : include this folder
--ignore file_filter : ignore matching files
--keep file_filter : keep matching files
--select file_filter : select only matching files
--abort : abort on errors
--verbose : show the processing messages
```

### Examples

```bash
dub --backup DATA_FOLDER/ REPOSITORY_FOLDER/
```

Backups the data files into the default archive of this repository.

```bash
dub --backup DATA_FOLDER/ REPOSITORY_FOLDER/ SUNDAY --exclude "/TEMP/"
```

Backups the data files into the `SUNDAY` archive of this repository, excluding the `TEMP` root folder.

```bash
dub --check DATA_FOLDER/ REPOSITORY_FOLDER/ SUNDAY
```

Checks the latest snapshot of the `SUNDAY` archive of this repository.

```bash
dub --compare DATA_FOLDER/ REPOSITORY_FOLDER/ SUNDAY
```

Compares the data files to the latest snapshot of the `SUNDAY` archive of this repository.

```bash
dub --restore DATA_FOLDER/ REPOSITORY_FOLDER/ SUNDAY
```

Restore the data files from the default archive.

```bash
dub --restore DATA_FOLDER/ REPOSITORY_FOLDER/ SUNDAY 202007052054138436
```

Restore the data files from the `202007191717441348878` snapshot of the `SUNDAY` archive of this repository.

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

0.2

## Author

Eric Pelzer (ecstatic.coder@gmail.com).

## License

This project is licensed under the GNU General Public License version 3.

See the [LICENSE.md](LICENSE.md) file for details.
