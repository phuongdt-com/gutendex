from subprocess import call
import json
import os
import platform
import shutil
import tarfile
import zipfile
from time import strftime, sleep
import sys

from django.conf import settings
from django.core.mail import send_mail
from django.core.management.base import BaseCommand, CommandError

from books import utils
from books.models import *


TEMP_PATH = settings.CATALOG_TEMP_DIR

URL = 'https://gutenberg.org/cache/epub/feeds/rdf-files.tar.bz2'
DOWNLOAD_PATH = os.path.join(TEMP_PATH, 'catalog.tar.bz2')

# Download settings
MAX_RETRIES = 5
RETRY_DELAY = 10  # seconds
IS_WINDOWS = platform.system() == 'Windows'

MOVE_SOURCE_PATH = os.path.join(TEMP_PATH, 'cache/epub')
MOVE_TARGET_PATH = settings.CATALOG_RDF_DIR

LOG_DIRECTORY = settings.CATALOG_LOG_DIR
LOG_FILE_NAME = strftime('%Y-%m-%d_%H%M%S') + '.txt'
LOG_PATH = os.path.join(LOG_DIRECTORY, LOG_FILE_NAME)


# This gives a set of the names of the subdirectories in the given file path.
def get_directory_set(path):
    directory_set = set()
    for directory_item in os.listdir(path):
        item_path = os.path.join(path, directory_item)
        if os.path.isdir(item_path):
            directory_set.add(directory_item)
    return directory_set


def log(*args):
    print(*args, flush=True)
    if not os.path.exists(LOG_DIRECTORY):
        os.makedirs(LOG_DIRECTORY)
    with open(LOG_PATH, 'a') as log_file:
        text = ' '.join(str(arg) for arg in args) + '\n'
        log_file.write(text)


def download_with_wget(url, dest_path, max_retries=MAX_RETRIES):
    """Download a file using wget with retry and resume support (Linux/Docker only)."""
    
    for attempt in range(1, max_retries + 1):
        log(f'    Attempt {attempt}/{max_retries} using wget...')
        
        # Delete partial file if exists (wget -c will resume, but file might be corrupt)
        if attempt > 1 and os.path.exists(dest_path):
            log('    Deleting partial file for fresh download...')
            os.remove(dest_path)
        
        # Use wget with:
        # -c: continue/resume partial downloads
        # -t 20: retry up to 20 times per attempt
        # --timeout=60: 60 second timeout per operation
        # --waitretry=10: wait 10 seconds between retries
        # --read-timeout=60: read timeout
        # --tries=20: same as -t
        # -O: output file
        # --progress=dot:mega: show progress in MB
        result = call(
            [
                'wget',
                '-c',
                '-t', '20',
                '--timeout=60',
                '--read-timeout=60',
                '--waitretry=10',
                '--progress=dot:mega',
                '-O', dest_path,
                url
            ],
            stdout=sys.stdout,
            stderr=sys.stderr
        )
        
        if result == 0:
            # Verify file exists and has reasonable size
            if os.path.exists(dest_path):
                file_size = os.path.getsize(dest_path)
                log(f'    Download complete! File size: {file_size / (1024*1024):.1f} MB')
                
                if file_size > 100 * 1024 * 1024:  # At least 100MB
                    return True
                else:
                    log(f'    ERROR: File too small ({file_size / (1024*1024):.1f} MB), expected >100MB')
            else:
                log('    ERROR: Download file not found!')
        else:
            log(f'    wget failed with exit code {result}')
        
        # Clean up for retry
        if os.path.exists(dest_path):
            os.remove(dest_path)
        
        if attempt < max_retries:
            log(f'    Waiting {RETRY_DELAY} seconds before retry...')
            sleep(RETRY_DELAY)
        else:
            log(f'    All {max_retries} attempts failed!')
            raise CommandError(f'Failed to download catalog after {max_retries} attempts')
    
    return False


def extract_tar_bz2(archive_path, extract_to):
    """Extract a tar.bz2 file using Python's tarfile module."""
    log('    Extracting with Python tarfile...')
    
    try:
        with tarfile.open(archive_path, 'r:bz2') as tar:
            # Count members for progress
            members = tar.getmembers()
            total = len(members)
            log(f'    Archive contains {total} entries')
            
            # Extract all
            tar.extractall(path=extract_to)
            
        log('    Extraction complete!')
        return True
    except Exception as e:
        log(f'    Extraction error: {str(e)}')
        return False


def extract_zip(archive_path, extract_to):
    """Extract a zip file using Python's zipfile module."""
    log('    Extracting with Python zipfile...')
    
    try:
        with zipfile.ZipFile(archive_path, 'r') as zip_ref:
            # Count members for progress
            members = zip_ref.namelist()
            total = len(members)
            log(f'    Archive contains {total} entries')
            
            # Extract all
            zip_ref.extractall(path=extract_to)
            
        log('    Extraction complete!')
        return True
    except Exception as e:
        log(f'    Extraction error: {str(e)}')
        return False


def copy_directory(src, dst):
    """Copy directory contents, replacing destination (cross-platform rsync alternative)."""
    log(f'    Copying files from {src} to {dst}...')
    
    # Remove destination contents first
    if os.path.exists(dst):
        for item in os.listdir(dst):
            item_path = os.path.join(dst, item)
            if os.path.isdir(item_path):
                shutil.rmtree(item_path)
            else:
                os.remove(item_path)
    else:
        os.makedirs(dst)
    
    # Copy new contents
    for item in os.listdir(src):
        src_path = os.path.join(src, item)
        dst_path = os.path.join(dst, item)
        
        if os.path.isdir(src_path):
            shutil.copytree(src_path, dst_path)
        else:
            shutil.copy2(src_path, dst_path)
    
    log('    Copy complete!')
    return True


def put_catalog_in_db():
    book_ids = []
    log('    Scanning catalog directories...')
    for directory_item in os.listdir(settings.CATALOG_RDF_DIR):
        item_path = os.path.join(settings.CATALOG_RDF_DIR, directory_item)
        if os.path.isdir(item_path):
            try:
                book_id = int(directory_item)
            except ValueError:
                # Ignore the item if it's not a book ID number.
                pass
            else:
                book_ids.append(book_id)
    book_ids.sort()
    book_directories = [str(id) for id in book_ids]
    
    total_books = len(book_directories)
    log(f'    Found {total_books} books to process...')

    processed = 0
    for directory in book_directories:
        id = int(directory)
        processed += 1

        # Log progress every 1000 books or at specific milestones
        if processed % 1000 == 0 or processed == total_books:
            percent = int(processed * 100 / total_books)
            log(f'    Processing books: {processed}/{total_books} ({percent}%)')

        book_path = os.path.join(
            settings.CATALOG_RDF_DIR,
            directory,
            'pg' + directory + '.rdf'
        )

        book = utils.get_book(id, book_path)

        try:
            '''Make/update the book.'''

            book_in_db = Book.objects.filter(gutenberg_id=id)

            if book_in_db.exists():
                book_in_db = book_in_db[0]
                book_in_db.copyright = book['copyright']
                book_in_db.download_count = book['downloads']
                book_in_db.media_type = book['type']
                book_in_db.title = book['title']
                book_in_db.save()
            else:
                book_in_db = Book.objects.create(
                    gutenberg_id=id,
                    copyright=book['copyright'],
                    download_count=book['downloads'],
                    media_type=book['type'],
                    title=book['title']
                )

            ''' Make/update the authors. '''

            authors = []
            for author in book['authors']:
                person = get_or_create_person(author)
                authors.append(person)

            book_in_db.authors.clear()
            for author in authors:
                book_in_db.authors.add(author)

            ''' Make/update the editors. '''

            editors = []
            for editor in book['editors']:
                person = get_or_create_person(editor)
                editors.append(person)

            book_in_db.editors.clear()
            for editor in editors:
                book_in_db.editors.add(editor)

            ''' Make/update the translators. '''

            translators = []
            for translator in book['translators']:
                person = get_or_create_person(translator)
                translators.append(person)

            book_in_db.translators.clear()
            for translator in translators:
                book_in_db.translators.add(translator)

            ''' Make/update the book shelves. '''

            bookshelves = []
            for shelf in book['bookshelves']:
                shelf_in_db = Bookshelf.objects.filter(name=shelf)
                if shelf_in_db.exists():
                    shelf_in_db = shelf_in_db[0]
                else:
                    shelf_in_db = Bookshelf.objects.create(name=shelf)
                bookshelves.append(shelf_in_db)

            book_in_db.bookshelves.clear()
            for bookshelf in bookshelves:
                book_in_db.bookshelves.add(bookshelf)

            ''' Make/update the formats. '''

            old_formats = Format.objects.filter(book=book_in_db)

            format_ids = []
            for format_ in book['formats']:
                format_in_db = Format.objects.filter(
                    book=book_in_db,
                    mime_type=format_,
                    url=book['formats'][format_]
                )
                if format_in_db.exists():
                    format_in_db = format_in_db[0]
                else:
                    format_in_db = Format.objects.create(
                        book=book_in_db,
                        mime_type=format_,
                        url=book['formats'][format_]
                    )
                format_ids.append(format_in_db.id)

            for old_format in old_formats:
                if old_format.id not in format_ids:
                    old_format.delete()

            ''' Make/update the languages. '''

            languages = []
            for language in book['languages']:
                language_in_db = Language.objects.filter(code=language)
                if language_in_db.exists():
                    language_in_db = language_in_db[0]
                else:
                    language_in_db = Language.objects.create(code=language)
                languages.append(language_in_db)

            book_in_db.languages.clear()
            for language in languages:
                book_in_db.languages.add(language)

            ''' Make/update subjects. '''

            subjects = []
            for subject in book['subjects']:
                subject_in_db = Subject.objects.filter(name=subject)
                if subject_in_db.exists():
                    subject_in_db = subject_in_db[0]
                else:
                    subject_in_db = Subject.objects.create(name=subject)
                subjects.append(subject_in_db)

            book_in_db.subjects.clear()
            for subject in subjects:
                book_in_db.subjects.add(subject)

            ''' Make/update summaries. '''

            old_summaries = Summary.objects.filter(book=book_in_db)

            summary_ids = []
            for summary in book['summaries']:
                summary_in_db = Summary.objects.filter(book=book_in_db, text=summary)
                if summary_in_db.exists():
                    summary_in_db = summary_in_db[0]
                else:
                    summary_in_db = Summary.objects.create(
                        book=book_in_db, text=summary
                    ) 
                summary_ids.append(summary_in_db.id)

            for old_summary in old_summaries:
                if old_summary.id not in summary_ids:
                    old_summary.delete()

        except Exception as error:
            book_json = json.dumps(book, indent=4)
            log(
                '  Error while putting this book info in the database:\n',
                book_json,
                '\n'
            )
            raise error


def get_or_create_person(data):
    person = Person.objects.filter(
        name=data['name'],
        birth_year=data['birth'],
        death_year=data['death']
    )

    if person.exists():
        person = person[0]
    else:
        person = Person.objects.create(
            name=data['name'],
            birth_year=data['birth'],
            death_year=data['death']
        )
    
    return person


def send_log_email():
    if not (settings.ADMIN_EMAILS or settings.EMAIL_HOST_ADDRESS):
        return

    log_text = ''
    with open(LOG_PATH, 'r') as log_file:
        log_text = log_file.read()

    email_html = '''
        <h1 style="color: #333;
                   font-family: 'Helvetica Neue', sans-serif;
                   font-size: 64px;
                   font-weight: 100;
                   text-align: center;">
            Gutendex
        </h1>

        <p style="color: #333;
                  font-family: 'Helvetica Neue', sans-serif;
                  font-size: 24px;
                  font-weight: 200;">
            Here is the log from your catalog retrieval:
        </p>

        <pre style="color:#333;
                    font-family: monospace;
                    font-size: 16px;
                    margin-left: 32px">''' + log_text + '</pre>'

    email_text = '''GUTENDEX

    Here is the log from your catalog retrieval:

    ''' + log_text

    send_mail(
        subject='Catalog retrieval',
        message=email_text,
        html_message=email_html,
        from_email=settings.EMAIL_HOST_ADDRESS,
        recipient_list=settings.ADMIN_EMAILS
    )


class Command(BaseCommand):
    help = 'This replaces the catalog files with the latest ones.'

    def handle(self, *args, **options):
        try:
            date_and_time = strftime('%H:%M:%S on %B %d, %Y')
            log('Starting script at', date_and_time)

            log('  Making temporary directory...')
            if os.path.exists(TEMP_PATH):
                # Check if there's a partial download to resume
                if os.path.exists(DOWNLOAD_PATH):
                    partial_size = os.path.getsize(DOWNLOAD_PATH)
                    log(f'    Found existing temp directory with partial download ({partial_size / (1024*1024):.1f} MB)')
                    log('    Will attempt to resume download...')
                else:
                    log('    Cleaning up existing temporary directory...')
                    shutil.rmtree(TEMP_PATH)
                    os.makedirs(TEMP_PATH)
            else:
                os.makedirs(TEMP_PATH)

            # On Windows, use pre-downloaded file; on Linux/Docker, download fresh
            if IS_WINDOWS:
                local_file = os.path.join(settings.BASE_DIR, 'data', 'rdf-files.tar.zip')
                log('  Using local catalog file...')
                log(f'    Path: {local_file}')
                
                if not os.path.exists(local_file):
                    raise CommandError(
                        f'Catalog file not found at {local_file}\n'
                        f'Please download it manually from:\n'
                        f'  {URL}\n'
                        f'And save it to: data/rdf-files.tar.zip'
                    )
                
                # Copy to temp path
                file_size = os.path.getsize(local_file)
                log(f'    File size: {file_size / (1024*1024):.1f} MB')
                shutil.copy2(local_file, DOWNLOAD_PATH)
                log('    Copied to temp directory!')
            else:
                log('  Downloading compressed catalog from Project Gutenberg...')
                log('    URL:', URL)
                log('    This file is approximately 125MB compressed and may take several minutes...')
                download_with_wget(URL, DOWNLOAD_PATH)

            # Verify download size (should be around 120-130 MB)
            file_size = os.path.getsize(DOWNLOAD_PATH)
            expected_min_size = 100 * 1024 * 1024  # 100 MB minimum
            
            if file_size < expected_min_size:
                log(f'  ERROR: Downloaded file is too small ({file_size / (1024*1024):.1f} MB)')
                log(f'  Expected at least {expected_min_size / (1024*1024):.0f} MB')
                log('  Deleting corrupt download for fresh retry...')
                os.remove(DOWNLOAD_PATH)
                raise CommandError('Downloaded file is incomplete. Please try again.')
            
            log('  Decompressing catalog (this may take a few minutes)...')
            
            # Use Python zipfile on Windows, system tar on Linux
            if IS_WINDOWS:
                success = extract_zip(DOWNLOAD_PATH, TEMP_PATH)
                if not success:
                    log('  ERROR: Extraction failed')
                    log('  The downloaded file may be corrupted.')
                    log('  Deleting corrupt download for fresh retry...')
                    os.remove(DOWNLOAD_PATH)
                    if os.path.exists(TEMP_PATH):
                        shutil.rmtree(TEMP_PATH)
                    raise CommandError('Extraction failed. Downloaded file may be corrupt. Please try again.')
            else:
                # Run tar silently (no verbose output) on Linux
                with open(os.devnull, 'w') as devnull:
                    result = call(
                        ['tar', 'fjx', DOWNLOAD_PATH, '-C', TEMP_PATH],
                        stdout=devnull,
                        stderr=devnull
                    )
                
                if result != 0:
                    log(f'  ERROR: tar extraction failed with exit code {result}')
                    log('  The downloaded file may be corrupted.')
                    log('  Deleting corrupt download for fresh retry...')
                    os.remove(DOWNLOAD_PATH)
                    if os.path.exists(TEMP_PATH):
                        shutil.rmtree(TEMP_PATH)
                    raise CommandError('Tar extraction failed. Downloaded file may be corrupt. Please try again.')
            
            # Verify extraction produced enough directories
            if os.path.exists(MOVE_SOURCE_PATH):
                extracted_count = len([d for d in os.listdir(MOVE_SOURCE_PATH) if os.path.isdir(os.path.join(MOVE_SOURCE_PATH, d))])
                log(f'  Extracted {extracted_count} book directories')
                
                if extracted_count < 50000:  # Should be ~73,000+
                    log(f'  ERROR: Only {extracted_count} books extracted, expected 50,000+')
                    log('  The download appears to be incomplete.')
                    log('  Deleting corrupt download for fresh retry...')
                    os.remove(DOWNLOAD_PATH)
                    if os.path.exists(TEMP_PATH):
                        shutil.rmtree(TEMP_PATH)
                    raise CommandError(f'Only {extracted_count} books extracted. Download incomplete. Please try again.')
            else:
                log('  ERROR: Extraction directory not found!')
                os.remove(DOWNLOAD_PATH)
                if os.path.exists(TEMP_PATH):
                    shutil.rmtree(TEMP_PATH)
                raise CommandError('Extraction failed - output directory not found.')
            
            log('  Decompression complete!')

            log('  Detecting stale directories...')
            if not os.path.exists(MOVE_TARGET_PATH):
                os.makedirs(MOVE_TARGET_PATH)
            new_directory_set = get_directory_set(MOVE_SOURCE_PATH)
            old_directory_set = get_directory_set(MOVE_TARGET_PATH)
            stale_directory_set = old_directory_set - new_directory_set
            log(f'    Found {len(stale_directory_set)} stale directories to remove')

            log('  Removing stale directories and books...')
            for directory in stale_directory_set:
                try:
                    book_id = int(directory)
                except ValueError:
                    # Ignore the directory if its name isn't a book ID number.
                    continue
                book = Book.objects.filter(gutenberg_id=book_id)
                book.delete()
                path = os.path.join(MOVE_TARGET_PATH, directory)
                shutil.rmtree(path)

            log('  Replacing old catalog files...')
            if IS_WINDOWS:
                # Use Python's shutil for cross-platform compatibility
                copy_directory(MOVE_SOURCE_PATH, MOVE_TARGET_PATH)
            else:
                # Use rsync on Linux for efficiency
                with open(os.devnull, 'w') as null:
                    with open(LOG_PATH, 'a') as log_file:
                        call(
                            [
                                'rsync',
                                '-va',
                                '--delete-after',
                                MOVE_SOURCE_PATH + '/',
                                MOVE_TARGET_PATH
                            ],
                            stdout=null,
                            stderr=log_file
                        )
            log('  File copy complete!')

            log('  Putting the catalog in the database...')
            put_catalog_in_db()

            log('  Removing temporary files...')
            shutil.rmtree(TEMP_PATH)

            log('Done!\n')
        except CommandError as error:
            # CommandError means download/extraction failed
            log('Error:', str(error))
            log('')
            # Clean up for fresh retry
            if os.path.exists(TEMP_PATH):
                shutil.rmtree(TEMP_PATH)
            raise  # Re-raise so container knows it failed
        except Exception as error:
            error_message = str(error)
            log('Error:', error_message)
            log('')
            if os.path.exists(TEMP_PATH):
                shutil.rmtree(TEMP_PATH)
            raise  # Re-raise so container knows it failed

        send_log_email()
