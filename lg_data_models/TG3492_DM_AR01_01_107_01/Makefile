include selected_profiles.mk

# HTML pages for the base data model (without selecting any object)
BASE_OBJECTS_HTML  := device2.html stb.html storage.html

# HTML pages for the final data model (after filtering the information based in selected_profiles.mk)
FINAL_OBJECTS_HTML := device-dt.html stb-dt.html storage-dt.html

# PATH to the different tools and additional data models
INCLUDE_XML  := ../../cwmp-zip 
REPORT_PL    := ../../cwmp-xml-tools/Report_Tool/report.pl

vpath %.xml source_xml

all: $(FINAL_OBJECTS_HTML)

device-dt.xml:
	$(REPORT_PL) -catalog catalog.xml -include $(INCLUDE_XML) -include source_xml $(addprefix -dtprofile ,$(DEVICE_DT_PROFILE)) -report=xml -showsyntax -outfile=final_models/device-dt.xml source_xml/device2.xml

%-dt.html: %-dt.xml
	$(REPORT_PL) -catalog catalog.xml -include $(INCLUDE_XML) -include source_xml -report=html -outfile=final_models/$@ final_models/$<

%.html: %.xml
	$(REPORT_PL) -include $(INCLUDE_XML) -report=html -outfile=base_models/$@ $<

clean:
	rm -f base_models/* final_models/*
