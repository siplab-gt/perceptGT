## Custom toolbox for extracting BrainSenseSurvey Data from Percept JSON files





Author: Dan Kim 





### A guide to using the perceptGT

*Purpose of this code: 
Extracts BrainSenseSurvey data from Medtronic's Percept Device JSON exports (LfpMontageTimeDomain and LfpMontage).
Saves it into matlab figures, plots(png), .m datafile, and a patient summary information table.

#### How to Use

**Tips and Tricks for matlab**

- To **close all** the figures that are generated at once rather than manually close them, type "close all" without the "" in matlab's command window.
- There program might lag if large amount of json files are put in due to the code generating figures. To close all the figures at once, use "close all" mentioned above.



0. Main file is the "perceptGT.m" file, user will only need to interact with this file. The user can select **a** single folder or multiple JSON files,** as long as they are inside the parent folder(Percept_files) or the parent folder itself.**
1. Set the pathname to the folder containing perceptGT.m file
    ex. 'C:/Users/rlaan/perceptGT/' -> 'your computer's path'
2. Run the matlab file, perceptGT.m
3. You can select multiple JSON files, the location of the JSON files should be within the Percept_files folder (the parent folder you'd like to have everything -- json files, results, etc). However, they don't have to be in the same folder as the toolbox.
 !Please keep the name of the json files as sub-XXXXXXXX_XX.json. Information is extracted from the filename
                                      Ex. sub-EMOPXXXX_test.json
                                      Ex2. sub-EMOPXXXX_.json
4. When successfully ran, the result will be folders consisting of each subject name, inside a folder called "Results" inside the parent folder(Percept_files)
   Inside each folder there will be PSD and LFP plots, spectrograms, .m data. Outside of the each patient specfic folder there will be a "subject_summary_combined.xlsx" file,
   which summarizes relevant subject information. "subject_summary_combined.xlsx" file will combine new information everytime a new patient is added (ran) automatically.
   This is information extracted from patient's Initial Group settings, which would be the settings the patient had been under influence of of before the BrainSenseSurvey.
