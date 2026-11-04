/*
 * Miscellaneous routines to get ARC running on non-MSDOS systems...
 *
 * You may copy and distribute this program freely,
 * under the terms of the General Public License.
 */

#include <stdio.h>
#include <stdarg.h>
#ifdef _WIN32
#include <errno.h>
#endif
#include <ctype.h>
#include "arc.h"

#include <string.h>
#if	BSD
#include <strings.h>
#endif

#if	MSDOS
#include <dir.h>
#include <stat.h>
#endif

#if	GEMDOS
#include <types.h>
#include <osbind.h>
#include <stat.h>

VOID 
exitpause()
{
	while (Cconis())
		Cnecin();
	fprintf(stderr, "Press any key to continue: ");
	fflush(stderr);
	Cnecin();
	fprintf(stderr, "\n");
}

int
chdir(dirname)
	char           *dirname;
{
	char           *i;
	int             drv;

	i = dirname;
	if ((i = index(dirname, ':')) != NULL) {
		drv = i[-1];
		i++;		/* Move past device spec */
		if (drv > '\'')
			drv -= 'a';
		else
			drv -= 'A';
		if (drv >= 0 && drv < 16)
			Dsetdrv(drv);
	}
	if (*i != '\0')
		return (Dsetpath(i));
}
#endif

#if	UNIX
#include <sys/types.h>
#if	SYSV
#include <dirent.h>
#define DIRECT dirent
#else
#include <sys/dir.h>
#define DIRECT direct
#endif
#include <sys/stat.h>
	int	rename(), unlink();
#include <fcntl.h>
#endif

#if	NEEDMEMSET
char	*
memset(s, c, n)		/* This came from SVR2? */
	char	*s;
	int	c, n;
{
	register int i;
	for(i=0;i<n;i++)
		s[i]=c;
	return(s);
}
#else
#include <memory.h>
#endif

#ifndef	__STDC__
char		*malloc();
#ifndef _AIX
int		free();
#endif
#endif
int             match();

/* Safe open for temp files */
FILE *
tmpopen(path)
	char *path;
{
	/* fdopen does not change the underlying descriptor's translation mode. */
#ifdef _WIN32
    int fd = open(path, O_CREAT | O_WRONLY | O_EXCL | O_BINARY, S_IRUSR | S_IWUSR);
#else
    int fd = open(path, O_CREAT | O_WRONLY | O_EXCL, S_IRUSR | S_IWUSR);
#endif
	if (fd < 0 )
		return NULL;
	return fdopen(fd, OPEN_W);
}

int
move(oldnam, newnam)
	char           *oldnam, *newnam;
{
	FILE           *fopen(), *old, *new;
#if	!_MTS
	struct stat     oldstat;
#endif
	VOID		filecopy();
#if	GEMDOS
	if (Frename(0, oldnam, newnam))
#else
	if (rename(oldnam, newnam))
#endif
#if	!_MTS
	{
		if (stat(oldnam, &oldstat))	/* different partition? */
			return (-1);
		old = fopen(oldnam, OPEN_R);
		if (old == NULL)
			return (-1);
		new = fopen(newnam, OPEN_W);
		if (new == NULL)
			return (-1);
		filecopy(old, new, oldstat.st_size);
		return(unlink(oldnam));
	}
	return 0;
#else
	return(-1);
#endif
}

static VOID
_makefn(source, dest)
	char           *source;
	char           *dest;
{
	int             j;
#if	MSDOS
	char	       *setmem();
#endif

	setmem(dest, 17, 0);	/* clear result field */
	for (j = 0; *source && *source != '.'; ++source)
		if (j < 8)
			dest[j++] = *source;
	for (j = 9; *source; ++source)
		if (j < 13)
			dest[j++] = *source;
}
/*
 * make a file name using a template 
 */

char           *
makefnam(rawfn, template, result)
	char           *rawfn;	/* the original file name */
	char           *template;	/* the template data */
	char           *result;	/* where to place the result */
{
	char            et[17], er[17], rawbuf[STRLEN], *i;

	*rawbuf = 0;
	strcpy(rawbuf, rawfn);
#if	_MTS
	i = rawbuf;
	if (rawbuf[0] == tmpchr[0]) {
		i++;
		strcpy(rawfn, i);
	} else
#endif
	if ((i = rindex(rawbuf, CUTOFF))) {
		i++;
		strcpy(rawfn, i);
	}
#if	DOS
	else if ((i = rindex(rawbuf, ':'))) {
		i++;
		strcpy(rawfn, i);
	}
#endif
	if (i)
		*i = 0;
	else
		*rawbuf = 0;

	_makefn(template, et);
	_makefn(rawfn, er);
	*result = 0;		/* assure no data */
	strcat(result, rawbuf);
	strcat(result, er[0] ? er : et);
	strcat(result, er[9] ? er + 9 : et + 9);
	return ((char *) &result[0]);
}

#ifdef _WIN32
/* MinGW supplies dirent enumeration, but not POSIX scandir/alphasort.
 * Own each selected entry and release the entire partial list on failure. */
static int
arc_alphasort(const void *left, const void *right)
{
    const struct dirent *const *a = left;
    const struct dirent *const *b = right;
    return strcmp((*a)->d_name, (*b)->d_name);
}

static int
arc_scandir(const char *path, struct dirent ***result,
            int (*select_entry)(struct dirent *),
            int (*compare)(const void *, const void *))
{
    DIR *directory = opendir(path);
    struct dirent *entry;
    struct dirent **list = NULL;
    int count = 0;
    if (directory == NULL) {
        return -1;
    }
    for (;;) {
        struct dirent **expanded;
        errno = 0;
        entry = readdir(directory);
        if (entry == NULL) {
            if (errno != 0) {
                goto failed;
            }
            break;
        }
        if (!select_entry(entry)) {
            continue;
        }
        expanded = realloc(list, (count + 1) * sizeof(*list));
        if (expanded == NULL) {
            goto failed;
        }
        list = expanded;
        list[count] = malloc(sizeof(*entry));
        if (list[count] == NULL) {
            goto failed;
        }
        memcpy(list[count++], entry, sizeof(*entry));
    }
    closedir(directory);
    if (count > 1) {
        qsort(list, count, sizeof(*list), compare);
    }
    *result = list;
    return count;
failed:
    while (count > 0) {
        free(list[--count]);
    }
    free(list);
    closedir(directory);
    return -1;
}
#endif

#if	NEED_ALPHASORT

int
alphasort(dirptr1, dirptr2)
	struct DIRECT **dirptr1, **dirptr2;
{
	return (strcmp((*dirptr1)->d_name, (*dirptr2)->d_name));
}

#endif

VOID
upper(string)
	char           *string;
{
	char           *p;

	for (p = string; *p; p++)
		if (islower(*p))
			*p = toupper(*p);
}
/* VARARGS1 */
VOID
arcdie(const char *s, ...)
{
	va_list args;
	fprintf(stderr, "ARC: ");
	va_start(args, s);
	vfprintf(stderr, s, args);
	va_end(args);
	fprintf(stderr, "\n");
#if	UNIX
	perror("UNIX");
#endif
#if	GEMDOS
	exitpause();
#endif
	exit(1);
}

#if	!_MTS

char           *
gcdir(dirname)
	char           *dirname;

{
	char           *getcwd();
#if	GEMDOS
	int             drv;
	char           *buf;
#endif
	if (dirname == NULL || strlen(dirname) == 0)
		dirname = (char *) malloc(1024);

#if	!GEMDOS
	getcwd(dirname, 1024);
#else
	buf = dirname;
	*buf++ = (drv = Dgetdrv()) + 'A';
	*buf++ = ':';
	Dgetpath(buf, 0);
#endif
	return (dirname);
}

#if	UNIX
char           *pattern;	/* global so that fmatch can use it */
#endif

char           *
dir(filename)		/* get files, one by one */
	char           *filename;	/* template, or NULL */
{
#if	GEMDOS
	static int      Nnum = 0;
#if	__GNUC__
#define	d_fname	dta_name	/* Wish these libraries would agree on names */
#define DMABUFFER	_DTA
#endif
	static DMABUFFER dbuf, *saved;
	char           *name;
	if (Nnum == 0) {	/* first call */
		saved = (DMABUFFER *) Fgetdta();
		Fsetdta(&dbuf);
		if (Fsfirst(filename, 0) == 0) {
			name = malloc(FNLEN);
			strcpy(name, dbuf.d_fname);
			Nnum++;
			return (name);
		} else {
			Fsetdta(saved);
			return (NULL);
		}
	} else {
		if (Fsnext() == 0) {
			name = malloc(FNLEN);
			strcpy(name, dbuf.d_fname);
			return (name);
		} else {
			Nnum = 0;
			Fsetdta(saved);
			return (NULL);
		}
	}
}
#else
	static struct DIRECT **namelist;
	static char   **NameList;
	static char	namecopy[STRLEN], *dirname;
#if	UNIX && !defined(_WIN32)
	int             alphasort();
	int             scandir();
#endif				/* UNIX */
	int             fmatch();
	static int      Nnum = 0, ii;


	if (Nnum == 0) {	/* first call */
		strcpy(namecopy,filename);
		if((pattern=rindex(namecopy,CUTOFF))) {
			*pattern = 0;
			pattern++;
			dirname = namecopy;
		} else {
			pattern = filename;
			dirname = ".";
		}
#ifdef _WIN32
        Nnum = arc_scandir(dirname, &namelist, fmatch, arc_alphasort);
#else
		Nnum = scandir(dirname, &namelist, fmatch, alphasort);
#endif
        if (Nnum < 0) {
            arcdie("Cannot enumerate directory %s", dirname);
        }
		NameList = (char **) malloc(Nnum * sizeof(char *));
		for (ii = 0; ii < Nnum; ii++) {
			(NameList)[ii] = malloc(strlen(namelist[ii]->d_name) + 1);
			strcpy((NameList)[ii], namelist[ii]->d_name);
		}
		ii = 0;
	}
	if (ii >= Nnum) {	/* all out of files */
		if (Nnum) {	/* there were some files found */
			for (ii = 0; ii < Nnum; ii++)
				free(namelist[ii]);
			free(namelist);
		}
		Nnum = 0;
		return (NULL);
	} else {
		return ((NameList)[ii++]);
	}
}

/*
 * Filename match - here, * matches everything 
 */

int
fmatch(direntry)
	struct DIRECT  *direntry;
{
	char           *string;

	string = direntry->d_name;

	if (!strcmp(pattern, "") || !strcmp(pattern, "*.*") || !strcmp(pattern, "*"))
		return (1);
	return (match(string, pattern));
}
#endif				/* GEMDOS */
#else
/* dir code for MTS under Bell Labs C... */

char           *
dir(filepattern)
	char           *filepattern;	/* template or NULL */
{
#if	USECATSCAN
	fortran VOID    catscan(), fileinfo();

	struct catname {
		short           len;
		char            name[257];
	}               pattern;

	struct catval {
		int             maxlen;
		int             actlen;
		char            name[257];
	}               catreturn;

	char           *i;
	int             j, RETCODE;

	static int      catptr = 0;
	static int      catflag = 0x200;
	static int      cattype = 1;
	static int      patflag = 0;

	catreturn.maxlen = 256;

	if (patflag) {
		patflag = 0;
		catptr = 0;
		return (NULL);
	}
	if (filepattern) {
		strcpy(pattern.name, filepattern);
		pattern.len = strlen(filepattern);
		if (!index(filepattern, '?'))
			patflag = 1;
	}
	if (patflag) {
		fileinfo(&pattern, &cattype, "CINAME  ", &catreturn, _retcode RETCODE);
		catptr = RETCODE ? 0 : 1;
	} else
		catscan(&pattern, &catflag, &cattype, &catreturn, &catptr);

	if (!catptr)
		return (NULL);
	else {
		char           *k;

/*		k = index(catreturn.name, ' ');
		if (k)
			*k = 0;
		else {		This seems unnecessary now	*/
			j = catreturn.actlen;
			catreturn.name[j] = 0;
/*		}		*/
		k = catreturn.name;
		if (*k == tmpchr[0])
			k++;
		else if ((k = index(catreturn.name, sepchr[0])))
			k++;
		else
			k = catreturn.name;
		j = strlen(k);
		i = malloc(++j);
		strcpy(i, k);
		return (i);
	}
#else
	fortran VOID    gfinfo();
	static char     gfname[24];
	static char     pattern[20];
	static int      gfdummy[2] = {
				      0, 0
	},              gfflags;
	int             i, RETCODE;
	char           *j, *k;

	if (filepattern) {
		strcpy(pattern, filepattern);
		strcat(pattern, " ");
		for (i = 20; i < 24; i++)
			gfname[i] = '\0';
		if (index(pattern, '?'))
			gfflags = 0x0C;
		else
			gfflags = 0x09;
	} else if (gfflags == 0x09)
		return (NULL);

	gfinfo(pattern, gfname, &gfflags, gfdummy, gfdummy, gfdummy, _retcode RETCODE);
	if (RETCODE)
		return (NULL);
	else {
		k = index(gfname, ' ');
		*k = '\0';
		k = gfname;
		if (gfname[0] == tmpchr[0])
			k++;
		else if ((k = index(gfname, sepchr[0])))
			k++;
		else
			k = gfname;
		i = strlen(k);
		j = malloc(++i);
		strcpy(j, k);
		return (j);
	}
#endif
}

int
unlink(path)
	char           *path;	/* name of file to delete */
{
	fortran VOID    destroy();
	int             RETCODE;

	char            name[258];

	strcpy(name, path);
	strcat(name, " ");
	destroy(name, _retcode RETCODE);
	if (RETCODE)
		return (-1);
	else
		return (0);
}
#endif
