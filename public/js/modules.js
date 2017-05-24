
/* Custom modules for page controls */

/* GLOBAL */

	/* 
		description:
		assign name (minus fileType) of uploaded file 
		to textbox described by id = hashfile_name

		trigger:
		onload event by input of type file
	*/
	function setFileName(){
		var fileName = $('input[type=file]').val().split('\\').pop();
		$('#hashfile_name').val(fileName.split('.').shift());
	}

/* SPECIFIC */


	