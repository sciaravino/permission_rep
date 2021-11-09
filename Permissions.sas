cas;
caslib _all_ assign;

%let BASE_URI=%sysfunc(getoption(servicesbaseurl));
/* Change the print to destination  */
proc printto log='/home/saciar/log86.txt' new; 
run;

filename resp temp;
/* Grab all of the folders in the system */
proc http url="&BASE_URI/folders/folders?limit=9999"
                method='get'
                oauth_bearer=sas_services
                out=resp;
run; 

libname resp json fileref=resp;

/* Get count of folders */
proc sql ;
	select count(*) into: obs_cnt
	from resp.items;
quit;

/* Assign two tables for the upcoming macro */
data fullperm;
stop;
run;

data list;
length name $140.;
stop;
run;


%PUT &obs_cnt;

%Macro api_loop;
	%DO i = 1 %to &obs_cnt;
/* Need to get the json body of ["/folders/folders/uniqueid"] for the POST request */
		filename test temp;
		data x;
			file test;
			set resp.items;
			if _n_ = &i;
			json = cats('[', quote(cats('/folders/folders/', id)), ']');
			folderURI = cats('/folders/folders/', id);
			put json;
		run;
		
/* Assign the folderURI as a macro variable	 */
		proc sql noprint;
			select folderURI into: folderURI
			from x;
		quit;
			
/* Make the POST request to get the permissions json response */
		filename respo temp;
		proc http method="POST"
				oauth_bearer=sas_services
				url="&BASE_URI/authorization/decision"
				ct="application/vnd.sas.uriarray+json"
				in=test
				out=respo;
		run;
			
			libname respo json fileref=respo;
			filename respo clear; 			
						
/* Combine outputs to dataset */
			
			data json_tables;
			set sashelp.vtable;
			where libname="RESPO" and scan(memname,-1,"_") in ("PRINCIPAL","CREATE","DELETE","REMOVE","SECURE","UPDATE","ADD","READ");
			type =scan(memname,-1,"_");
			call symput(type,memname);
			run;
			
			data column_name;
			set sashelp.vcolumn;
			where libname="RESPO" and memname ="&PRINCIPAL" and varnum=1;
			run;
			
			proc sql noprint ;
				select name into: folder_name
				from column_name;
			quit;
			
			%PUT &folder_name;
			%PUT &principal;
			

			%IF &i =1 %THEN %DO;
				data join&i;
				merge RESPO.&principal
				RESPO.&create (rename=(result=create) keep=result &folder_name)
				RESPO.&delete (rename=(result=delete) keep=result &folder_name)
				RESPO.&remove (rename=(result=remove) keep=result &folder_name)
				RESPO.&secure (rename=(result=secure) keep=result &folder_name)
				RESPO.&update (rename=(result=update) keep=result &folder_name)
				RESPO.&add (rename=(result=add) keep=result &folder_name)
				RESPO.&read (rename=(result=read) keep=result &folder_name);
				by &folder_name;
				run;

				data fullperm;
					LENGTH folderURI $80.;
					set join&i (drop=&folder_name);
					folderURI = "&folderURI";
				run;

				%END;
				
				%ELSE %DO;
				data join&i;
				merge RESPO.&principal
				RESPO.&create (rename=(result=create) keep=result &folder_name)
				RESPO.&delete (rename=(result=delete) keep=result &folder_name)
				RESPO.&remove (rename=(result=remove) keep=result &folder_name)
				RESPO.&secure (rename=(result=secure) keep=result &folder_name)
				RESPO.&update (rename=(result=update) keep=result &folder_name)
				RESPO.&add (rename=(result=add) keep=result &folder_name)
				RESPO.&read (rename=(result=read) keep=result &folder_name);
				by &folder_name;
				run;	

				data join&i;
					LENGTH folderURI $80.;
					set join&i (drop=&folder_name);
					folderURI = "&folderURI";
				run;		
/*  */
/* options missing=''; */
				data fullperm;
					LENGTH folderURI $80. ordinal_principal 8 version 8 type $32. name $32. create delete remove secure update add read $12. ;
					set fullperm join&i ;
/* 					if missing(cats(of _all_)) then delete; */
				run;

	
				%END;
			
		proc delete data=join&i;
		run;

		libname respo clear;
	%END;

%Mend api_loop;

%api_loop;

/* Scan the folder URI for the id value to join the full permissions with the resp.items details */
data subid;
	set fullperm;
	id = scan(folderURI, 3, '/');
run;
		
proc sql;
	create table left_sql as
	select a.*,	b.name as labeled, b.ordinal_items, b.description, b.createdby, b.modifiedby, b.creationtimestamp, b.modifiedtimestamp
		from subid a
			left join
				resp.items b
				on a.id = b.id
			order by ordinal_items, ordinal_principal;
quit;

proc delete data=public.permrep;
run;

data public.permrep (promote=YES);
	set left_sql;
run;
 
proc casutil incaslib="public";
   save casdata="permrep" outcaslib="public" replace; 
run;