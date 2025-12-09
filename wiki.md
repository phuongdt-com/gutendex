Installation Guide
Gareth edited this page on Oct 4 · 13 revisions
This guide is for modern, UNIX-based systems such as Linux and macOS. (I recommend Ubuntu 24.04.)

1. Install Prerequisites
You must have these installed:

Python 3.12+ with pip and package venv
(Ubuntu 24: apt install python3-pip && apt install python3-venv)
Postgres 16+ with support for psycopg2
(Ubuntu 24: apt install postgresql)
2. Make the Database
Switch to the user for Postgres, if necessary. In some cases, such as macOS with Postgres.app, this could be your default user. In other cases, this shell command might work:

su postgres
Next, make the Gutendex database:

createdb gutendex
(You can replace gutendex above with something else if you update the DATABASE_NAME environment variable accordingly, described below.)

Make a Postgres user for the database, and remember the password that you enter:

createuser -P gutendex
(You can also replace gutendex above with another user name, updating the DATABASE_USER environment variable below.)

Now, open Postgres on the command line with

psql
and enter these commands separately:

GRANT ALL PRIVILEGES ON DATABASE gutendex TO gutendex;
\c gutendex;
GRANT ALL ON SCHEMA public TO gutendex;
(If you entered your own database and/or user name earlier, replace gutendex above with them, respectively.)

Exit Postgres by pressing ctrl+d on your keyboard.

Switch back to the root user by pressing ctrl+d again.

3. Install Python Packages
Python packages required by Gutendex are listed with their version numbers in requirements.txt.

I recommend that you install these with pip in a virtual environment created with venv. You can do this as the root user in the Gutendex root directory like this:

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
This creates a new directory, venv, which holds the files necessary files for the virtual environment, and activates that environment. Later, when you are done working with Gutendex, you can enter the deactivate command to exit the virtual environment.

4. Make Environment Variables
A number of environment variables are used by Gutendex, and they are listed in gutendex/.env.template.

I recommend that you copy this file to a new file called .env and edit the values after the = sign on each line with the proper data. The Django project will automatically read this file when the server starts.

Some of the variables require a way to send email. I recommend Mailgun.

Descriptions of each required variable are below.

ADMIN_EMAILS
This is a list of email addresses of the project administrators in ADMIN_NAMES. Addresses should be separated by commas and be in the same quantity and order as the names in ADMIN_NAMES.

ADMIN_NAMES
This is a list of names of project administrators that will be emailed with catalog download logs and various Django messages, such as security warnings. Names should be separated with commas.

ALLOWED_HOSTS
This is a list of domains and IP addresses on which you allow Gutendex to be served. Domains should be separated by commas. To allow any subdomain of a domain, add a . before the domain (e.g. .gutendex.com allows gutendex.com, api.gutendex.com, etc.). I recommend including 127.0.0.1 and/or localhost for development and testing on your local machine.

DATABASE_HOST
This is the domain or IP address on which your Postgres database runs. It is typically 127.0.0.1 for local databases.

DATABASE_NAME
This is the name of the Postgres database that you used. (Instructions for creating this database are above.) I recommend gutendex.

DATABASE_PASSWORD
This is the password for DATABASE_USER.

DATABASE_PORT
This is the port number on which the Gutendex database runs. This will typically be 5432.

DATABASE_USER
This is the name of a database user with all privileges for the Gutendex database. I recommend gutendex.

DEBUG
This is a Django setting for displaying useful debugging information. true will show this information in API responses when errors occur during development. It is important for security that you set this to false before serving Gutendex on a public address.

EMAIL_HOST
This is the address of the SMTP server that Gutendex will try to use when sending email. (For Mailgun, this is smtp.mailgun.org.)

EMAIL_HOST_ADDRESS
This is the email address where Gutendex email will appear to come from. (For Mailgun, this can probably be any email address.)

EMAIL_HOST_PASSWORD
This is the password for the the below EMAIL_HOST_USER. (For Mailgun, this is the 'Default Password' value in your Domain Information.)

EMAIL_HOST_USER
This is the user name that Gutendex will use to send email from the SMTP server in EMAIL_HOST. (For Mailgun, this is the 'Default SMTP Login' value in your Domain Information.)

MANAGER_EMAILS
This is a list of email addresses of the website managers in MANAGER_NAMES. Addresses should be separated by commas and be in the same quantity and order as the names in MANAGER_NAMES.

MANAGER_NAMES
This is a list of names of website managers that can be emailed with various Django messages. Names should be separated with commas.

MEDIA_ROOT
This is the path to a server directory where any API user media (currently nothing) can be stored.

SECRET_KEY
This is a password that Django uses for security reasons. It should be a long string of characters that should be kept secret. You do not need to copy or remember it anywhere.

STATIC_ROOT
This is the path to a server directory where website assets, such as CSS styles for HTML pages, are stored.

5. Migrate the Database
cd to the root directory of the project.

Set up the database for storing the catalog data. Run this in the virtual environment mentioned above:

./manage.py migrate
6. Populate the Database
Enter the Project Gutenberg catalog data into the Gutendex database. This takes a long time (several minutes on my machine):

./manage.py updatecatalog
This downloads a file archive of Project Gutenberg's catalog data and decompresses the files into a new directory, catalog_files. It places the contained files in catalog_files/rdf, and it stores a log in catalog_files/log and emails it to the administrators in the environment variables mentioned above.

If your database already contains catalog data, the above command will update it with any new or updated data from Project Gutenberg. I recommend that you schedule this command to run on your server daily – for example, using cron on Unix-like machines – to keep your database up-to-date.

7. Collect Static Files
To show styled HTML pages (i.e. the home page and error pages), you must put the necessary stylesheets into a static-file directory:

./manage.py collectstatic
8. Run the Server
Now you can serve your Django project. On your local machine, you can run do this with the following command for development and testing purposes:

./manage.py runserver
Serving Publicly
In a production environment, I recommend using the Apache v2 HTTP Server instead. You can install this on Ubuntu 24 for use with Django with the following command:

apt install apache2 libapache2-mod-wsgi-py3
Next, you need to configure Apache to serve

static files,
robots.txt,
any future user media, and
the web API itself.
You can do this by editing the file /etc/apache2/sites-available/000-default.conf on your server and adding the following lines before the line containing </VirtualHost>, but replacing /path/to/gutendex to the Gutendex path on your server:

	Alias /static /path/to/gutendex/static
	<Directory /path/to/gutendex/static>
		Require all granted
	</Directory>

	Alias /robots.txt /path/to/gutendex/static/robots.txt

	Alias /media /path/to/gutendex/media
	<Directory /path/to/gutendex/media>
		Require all granted
	</Directory>

	<Directory /path/to/gutendex/gutendex>
		<Files wsgi.py>
			Require all granted
		</Files>
	</Directory>

	WSGIDaemonProcess gutendex python-home=/path/to/gutendex/venv python-path=/path/to/gutendex
	WSGIProcessGroup gutendex
	WSGIScriptAlias / /path/to/gutendex/gutendex/wsgi.py
If you want to serve the website at a particular domain name or via HTTPS, additional configuration is required.

In any case, you also need to give Apache's web server user permission to access the Gutendex files. You can do this with the following command, again replacing /path/to/gutendex to the Gutendex path on your server:

chown :www-data /path/to/gutendex
You can now serve Gutendex with this command:

service apache2 restart
You should also collect the static files and run the above command again whenever you add or update Gutendex files.

Pages 2
Find a page or section…
Home
Installation Guide
1. Install Prerequisites
2. Make the Database
3. Install Python Packages
4. Make Environment Variables
ADMIN_EMAILS
ADMIN_NAMES
ALLOWED_HOSTS
DATABASE_HOST
DATABASE_NAME
DATABASE_PASSWORD
DATABASE_PORT
DATABASE_USER
DEBUG
EMAIL_HOST
EMAIL_HOST_ADDRESS
EMAIL_HOST_PASSWORD
EMAIL_HOST_USER
MANAGER_EMAILS
MANAGER_NAMES
MEDIA_ROOT
SECRET_KEY
STATIC_ROOT
5. Migrate the Database
6. Populate the Database
7. Collect Static Files
8. Run the Server
Serving Publicly
Clone this wiki locally
