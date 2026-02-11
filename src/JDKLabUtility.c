#include "jansson.h"
#include <stdio.h>
#include <string.h>

void print_node(json_t *node, int level) {
    json_t * name = json_object_get(node,"name");
    printf("%*s\n", level,json_string_value(name));
    json_t * json_t_child = json_object_get(node,"children");
    int i;
    for (i = 0; i < json_array_size(json_t_child); i++) {
        json_t * child = json_array_get(json_t_child,i);
        level+=2;
        print_node(child, level);
        level-=2;
    }
}

void build_tree (int tree_node, json_t *json_node) {
    json_object_set_new(json_node, "length", json_real(nodes[tree_node].branch));
    json_object_set_new(json_node, "name", json_string(nodes[tree_node].name));
    json_object_set_new(json_node, "id", json_integer(nodes[tree_node].nodeID));
    if (nodes[tree_node].nson > 0) {
        json_t * json_t_child = json_array();
        json_object_set_new(json_node, "children", json_t_child);
        int i;
        for (i = 0; i < nodes[tree_node].nson; i++) {
            json_t * child = json_object();
            json_array_append(json_t_child, child);
            build_tree(nodes[tree_node].sons[i], child);
            json_decref(child);
        }
    }
}

// output tree in JSON format
char* outputTreeInJson() {
    int i;
    for(i=0; i < tree.nnode; i++){
        if(nodes[i].nson == 0) {
        nodes[i].nodeID = i;
        nodes[i].name = com.spname[i];
    }
    if(nodes[i].nson > 0){
        nodes[i].nodeID = i;
        if(nodes[i].father == -1) {nodes[i].name = "Root"; nodes[i].branch = 0;}
        else nodes[i].name = "Internal";
        }
    }

    json_t * json_root = json_object();
    build_tree(tree.root, json_root);
    char* tree = json_dumps(json_root, JSON_COMPACT|JSON_SORT_KEYS);
    
    json_decref(json_root);

    return tree;
}

// makeup data variable with value for JS
char* makeupDataOutput(char *data, char *type){
    char *line = (char*)malloc((1+strlen(type))*sizeof(char)); 
    strcpy(line, type);

    line = (char*)realloc(line, (strlen(line)+4)*sizeof(char));
    strcat(line, " = ");

    line = (char*)realloc(line, (strlen(line)+strlen(data)+1)*sizeof(char));
    strcat(line, data);

    return line;
}

void generateHTML(char *file, char *templateFile, char* moreFile, int* selectedBranchPairs, int numOfSelectedBranchPairs) {
    char *htmlFileNameFullPath;
    if(moreFile == NULL){
        htmlFileNameFullPath = (char*)malloc((9+strlen(com.htmlFileName))*sizeof(char)); 
        strcpy(htmlFileNameFullPath, "UI/User/");
        strcat(htmlFileNameFullPath, com.htmlFileName);
        htmlFileNameFullPath[8+strlen(com.htmlFileName)] = '\0';
    }else{
        htmlFileNameFullPath = (char*)malloc((9+strlen(moreFile))*sizeof(char)); 
        strcpy(htmlFileNameFullPath, "UI/User/");
        strcat(htmlFileNameFullPath, moreFile);
        htmlFileNameFullPath[8+strlen(moreFile)] = '\0';
    }

    FILE *template, *newHTML;
    template = fopen(templateFile, "r");
    newHTML = fopen(htmlFileNameFullPath, "w");

    int lline = 1024, i=0;
    char line[lline];
    for(;;){
        if (fgets(line, lline, template) == NULL) break;
            fprintf(newHTML, "%s", line);
        if (strstr(line,"@dataTag")) {
            fprintf(newHTML, "<script src=\"%s\"></script>\n", strstr(file,"User/")+5);
        }
        if (strstr(line,"@tableAndPlot")){
            for(i=0; i<numOfSelectedBranchPairs; i++){
                int b1 = selectedBranchPairs[i*3], b2 = selectedBranchPairs[i*3+1];
                fprintf(newHTML, 
                    "<div id=\"BP_%dx%d-barPlot\"></div>\n"
                    "<div data-collapse style=\"float:centre\">\n"
                    "\t<h4 style=\"float:centre; margin-left:500px\"> Sites <br> Branch Pair: %d..%d </h4>\n"
                    "<div id=\"BP_%dx%d-sheet\" style=\"float:centre; margin-left:150px; margin-right:150px\"></div>\n"
                    "</div><br>\n\n",
                    b1, b2, b1, b2, b1, b2);               
            }
            if (numOfSelectedBranchPairs == 0) {
                fprintf(newHTML,
                    "<h4 style=\"float:left; margin-left:70px\"> Branch Pairs must be provided for this plot (see the <i>--branch-pairs</i> parameter)</h4>");
            }
        }
        if (strstr(line,"@rateVsDivPlot")){
            for(i=0; i<numOfSelectedBranchPairs; i++){
                int b1 = selectedBranchPairs[i*3], b2 = selectedBranchPairs[i*3+1];
                fprintf(newHTML, 
                    "<div id=\"BP_%dx%d-barPlot\"></div>\n"
                    "<div data-collapse style=\"float:centre\">\n"
                    "\t<h4 style=\"float:centre; margin-left:500px\"> Sites <br> Branch Pair: %d..%d </h4>\n"
                    "<div id=\"BP_%dx%d-sheet\" style=\"float:centre; margin-left:150px; margin-right:150px\"></div>\n"
                    "</div><br>\n\n",
                    b1, b2, b1, b2, b1, b2);
            }
        }
        if (strstr(line, "@plot")) {
            for (i=0; i < numOfSelectedBranchPairs; i++) {
                int b1 = selectedBranchPairs[i*3], b2 = selectedBranchPairs[i*3+1];
                fprintf(newHTML, 
                    "<div id=\"figure\" style=\"float:left; width:550px; z-index:2000; background-color: #ffffff; \">\n"
                    "<h4 style=\"float:left; margin-left:70px\"> Branch Pair: %d..%d </h4>\n"
                    "<div id=\"BP_%dx%d-data-plot\" style=\"margin-left: 10px; float:left; width:540px; outline: 0 !important; border: 0 !important; \"></div>\n</div>\n", b1,b2, b1, b2);
            }
            if (numOfSelectedBranchPairs == 0) {
                fprintf(newHTML,
                    "<h4 style=\"float:left; margin-left:70px\"> Branch Pairs must be provided for this plot (see the <i>--branch-pairs</i> parameter)</h4>");
            }
        }
    }

    fclose(newHTML);
    fclose(template);
}

int cmpfunc (const void * x, const void * y){
    double xx = *(double*)x, yy = *(double*)y;
    if (xx < yy) return -1;
    if (xx > yy) return  1;
    return 0;
}

void calculateRegression(double *pDivergent, double *pAllConvergent, int numBranchPairs, double *k, double *b){

    int i,j, counter = 0, cutoff = 0, index = 0;
    double xdelta, ydelta, slope;

    /* Pass 1: count non-zero slopes (avoids O(n^2) memory allocation that
       overflows int and requires tens of GB for large trees) */
    for(i=0; i<numBranchPairs; i++){
        for(j=i+1; j<numBranchPairs; j++){
            xdelta = pDivergent[i]-pDivergent[j];
            ydelta = pAllConvergent[i]-pAllConvergent[j];
            if(xdelta==0 && ydelta==0) continue;
            slope = ydelta/xdelta;
            if(slope == -1) continue;
            if(slope != 0) counter++;
        }
    }

    /* Pass 2: collect non-zero slopes directly into vector */
    double *vector = (double*)malloc((size_t)counter*sizeof(double));
    for(i=0; i<numBranchPairs; i++){
        for(j=i+1; j<numBranchPairs; j++){
            xdelta = pDivergent[i]-pDivergent[j];
            ydelta = pAllConvergent[i]-pAllConvergent[j];
            if(xdelta==0 && ydelta==0) continue;
            slope = ydelta/xdelta;
            if(slope == -1) continue;
            if(slope != 0) {
                vector[index]=slope;
                index++;
            }
        }
    }
    qsort(vector, counter, sizeof(double), cmpfunc);

    for(i=0; i<counter; i++){
        if(vector[i] >= -1){
            cutoff=i-1;
            break;
        }
    }

    if(counter%2 == 0)
        *k = 0.5*(vector[counter/2+cutoff] + vector[counter/2+cutoff+1]);
    else
        *k = vector[(counter+1)/2+cutoff];
    
    free(vector);
    double *temp = (double*)malloc(numBranchPairs*sizeof(double));
    for(i=0; i<numBranchPairs; i++){
        temp[i] = pAllConvergent[i] - (*k)*pDivergent[i];
    }
    qsort(temp, numBranchPairs, sizeof(double), cmpfunc);
    if(numBranchPairs%2==0)
        *b = (temp[numBranchPairs/2]+temp[numBranchPairs/2-1])/2;
    else
        *b = temp[numBranchPairs/2];

    free(temp);
}

void outputDataInJS(int *node1, int *node2, double *pDivergent, double *pAllConvergent, 
                    float *siteSpecificMap, int *selectedBranchPairs,
                    int numOfSelectedBranchPairs, int numBranchPairs, int lst,
                    double *postNumSub, int *siteClass){

    // calculate regression slope and intercept
    double k, b;
    
    calculateRegression(pDivergent, pAllConvergent, numBranchPairs, &k, &b);

    // format data of xPoints, yPoints and labels for scatter plot
    int ig, h;
    char *xPoints = (char*)malloc(numBranchPairs*20*sizeof(char));
    char *yPoints = (char*)malloc(numBranchPairs*20*sizeof(char));
    char *labels = (char*)malloc(numBranchPairs*25*sizeof(char));
    char *xPostNumSub = (char*)malloc(lst*20*sizeof(char));    // Look for short name to better describe these points
    char *ySiteClass = (char*)malloc(lst*20*sizeof(char));
    strcpy(xPoints, "[ ");
    strcpy(yPoints, "[ ");
    strcpy(labels, "[ ");
    strcpy(xPostNumSub, "[ ");
    strcpy(ySiteClass, "[ ");
    
    for (ig=0;ig<numBranchPairs-1;ig++) {
        sprintf(xPoints + strlen(xPoints), "%.6f, ", pDivergent[ig]);
        sprintf(yPoints + strlen(yPoints), "%.6f, ", pAllConvergent[ig]);
        sprintf(labels + strlen(labels), "\"%d..%d x %d..%d\", ", nodes[node1[ig]].father, node1[ig], nodes[node2[ig]].father, node2[ig]);
    }

    sprintf(xPoints + strlen(xPoints), "%f", pDivergent[ig]);
    sprintf(yPoints + strlen(yPoints), "%f", pAllConvergent[ig]);
    sprintf(labels + strlen(labels), "\"%d..%d x %d..%d\"", nodes[node1[ig]].father, node1[ig], nodes[node2[ig]].father, node2[ig]);
    strcat(xPoints, " ]");
    strcat(yPoints, " ]");
    strcat(labels, " ]");

    for (h=0;h<lst-1;h++) {
        sprintf(xPostNumSub + strlen(xPostNumSub), "%.6f, ", postNumSub[h]);
        sprintf(ySiteClass + strlen(ySiteClass), "%d, ", (int)siteClass[h]);
    }
    sprintf(xPostNumSub + strlen(xPostNumSub), "%.6f", postNumSub[lst-1]);
    sprintf(ySiteClass + strlen(ySiteClass), "%d", siteClass[lst-1]);
    strcat(xPostNumSub, " ]");
    strcat(ySiteClass, " ]");

    // add name of dataset at beginning to make the string like 'var foo = [...];'
    char *tree = outputTreeInJson();
    tree = makeupDataOutput(tree, "tree");
    xPoints = makeupDataOutput(xPoints, "xPoints");
    yPoints = makeupDataOutput(yPoints, "yPoints");
    labels = makeupDataOutput(labels, "labels");
    xPostNumSub = makeupDataOutput(xPostNumSub, "xPostNumSub");
    ySiteClass = makeupDataOutput(ySiteClass, "ySiteClass");
    
    // parse and embellish user-input html name for output
    int pos = strchr(com.htmlFileName,'.')-com.htmlFileName;
    char *file = (char*)malloc((16+pos)*sizeof(char));
    char temp[pos+1];
    strncpy(temp, com.htmlFileName, pos);
    temp[pos] = '\0';
    strcpy(file, "UI/User/");
    strcat(file, temp);
    strcat(file, "Data.js");
    
    /*** start to write data to JS file **/
    FILE *dataFile = fopen(file, "w");

    // to obtain corresponding sheet-[..].html file name
    char *sheetFile = (char*)malloc((7+strlen(com.htmlFileName))*sizeof(char));
    sheetFile[7+strlen(com.htmlFileName) - 1] = '\0';
    strcpy(sheetFile, "sheet-");
    strcat(sheetFile, com.htmlFileName);

    // to obtain corresponding siteSpecific-[..].html file name
    char *siteSpecificFile = (char*)malloc((14+strlen(com.htmlFileName))*sizeof(char));
    siteSpecificFile[14+strlen(com.htmlFileName) - 1] = '\0';
    strcpy(siteSpecificFile, "siteSpecific-");
    strcat(siteSpecificFile, com.htmlFileName);


    // to obtain corresponding rateVsDiversity-[..].html file name
    char *rateVsDiversityFile = (char*)malloc((17+strlen(com.htmlFileName))*sizeof(char));
    rateVsDiversityFile[17+strlen(com.htmlFileName) - 1] = '\0';
    strcpy(rateVsDiversityFile, "rateVsDiversity-");
    strcat(rateVsDiversityFile, com.htmlFileName);

    // to obtain corresponding rateVsProbConvergence-[..].html file name
    char *rateVsProbConvergenceFile = (char*)malloc((23+strlen(com.htmlFileName))*sizeof(char));
    rateVsProbConvergenceFile[23+strlen(com.htmlFileName) - 1] = '\0';
    strcpy(rateVsProbConvergenceFile, "rateVsProbConvergence-");
    strcat(rateVsProbConvergenceFile, com.htmlFileName);

    // write dynamic trigger functions to open sheet and siteSpecific html
    fprintf(dataFile,
        "function openSheetPopup() { \n"
        "\t    branchPairTab = window.open(\"%s\", \"branchPairTabViewer\", strWindowFeatures);\n"
        "\t    var timer = setInterval(function() {\n"
        "\t    if(branchPairTab.closed) {  \n"
        "\t        clearInterval(timer);  \n"
        "\t        $(\".hilighted\").attr({ \n"
        "\t            fill: '#0000ff', \n"
        "\t            'fill-opacity': 0.3, \n"
        "\t            stroke: '#000000' \n"
        "\t        }); \n"
        "\t        $('.hilighted').each(function(i,v) { \n"
        "\t            t=$('#'+v.id).attr('class'); \n"
        "\t            $('#'+v.id).attr('class',t.replace(/ hilighted/g, \"\")); \n"
        "\t        }) \n"
        "\t    }; \n"
        "\t    }, 1000); \n"
        "}\n\n"
        "function openSiteSpecificPopup() {\n"
        "\t    siteSpecificTab = window.open(\"%s\",  \"siteSpecificTabViewer\", strWindowFeatures);\n"
        "}\n"
        "function openRateVsDiversityPopup() {\n"
        "\t    siteSpecificTab = window.open(\"%s\", \"rateVsDiversityTabViewer\", strWindowFeatures);\n"
        "}\n"
        "function openRateVsProbConvergencePopup() {\n"
        "\t    siteSpecificTab = window.open(\"%s\", \"rateVsProbConvergenceTabViewer\", strWindowFeatures);\n"
        "}\n\n", sheetFile, siteSpecificFile, rateVsDiversityFile, rateVsProbConvergenceFile);

    // write data to JS file
    fprintf(dataFile, "regressionSlope = %f;\n", k);
    fprintf(dataFile, "regressionIntercept = %f;\n", b);
    fprintf(dataFile, "numOfSelectedBranchPairs = %d;\n", numOfSelectedBranchPairs);
    fprintf(dataFile, "numOfSites = %d;\n", lst);
    fprintf(dataFile, "%s;\n%s;\n%s;\n%s;\n%s;\n%s;\n", tree, xPoints, yPoints, labels, xPostNumSub, ySiteClass);
    free(xPoints);
    free(yPoints);
    free(labels);
    free(xPostNumSub);
    free(ySiteClass);

    // format site-specific data and write to file
    char *siteSpecificBranchPairs = (char*)malloc((20*numOfSelectedBranchPairs+4)*sizeof(char));
    char *siteSpecificBranchPairsName = (char*)malloc((30*numOfSelectedBranchPairs+4)*sizeof(char));
    char *siteSpecificBranchPairsIDs = (char*)malloc((25*numOfSelectedBranchPairs+4)*sizeof(char));
    strcpy(siteSpecificBranchPairs, "[ ");
    strcpy(siteSpecificBranchPairsName, "[ ");
    strcpy(siteSpecificBranchPairsIDs, "[ ");
    if(numOfSelectedBranchPairs == 0){
        strcat(siteSpecificBranchPairs, "]");
        strcat(siteSpecificBranchPairsName, "]");
        strcpy(siteSpecificBranchPairsIDs, "[ ");
    }

    for(ig=0; ig<numOfSelectedBranchPairs; ig++){
        char *siteSpecificBP = (char*)malloc(lst*30*sizeof(char));
        strcpy(siteSpecificBP, "[ ");
        for(h=0; h<lst-1; h++){
            if((siteSpecificMap[ig*lst*2+h*2] != 0 || siteSpecificMap[ig*lst*2+h*2+1] != 0))
                sprintf(siteSpecificBP + strlen(siteSpecificBP), "[%d, %.6f, %.6f], ", h, siteSpecificMap[ig*lst*2+h*2], siteSpecificMap[ig*lst*2+h*2+1]);
        }
        if((siteSpecificMap[ig*lst*2+h*2] != 0 || siteSpecificMap[ig*lst*2+h*2+1] != 0))
            sprintf(siteSpecificBP + strlen(siteSpecificBP), "[%d, %.6f, %.6f] ", h, siteSpecificMap[ig*lst*2+h*2], siteSpecificMap[ig*lst*2+h*2+1]);
        strcat(siteSpecificBP, "]");

        char *branchPairIDs = (char*)malloc(20*sizeof(char));
        char *branchPairNames = (char*)malloc(30*sizeof(char));
        sprintf(branchPairIDs, "BP_%dx%d", selectedBranchPairs[ig*3], selectedBranchPairs[ig*3+1]);
        sprintf(branchPairNames, "\"Branch Pair: %d..%d\"", selectedBranchPairs[ig*3], selectedBranchPairs[ig*3+1]);
        siteSpecificBP = makeupDataOutput(siteSpecificBP, branchPairIDs);
        fprintf(dataFile, "%s;\n", siteSpecificBP);

        if(ig<numOfSelectedBranchPairs-1) {
            sprintf(siteSpecificBranchPairs + strlen(siteSpecificBranchPairs), "%s, ", branchPairIDs);
            sprintf(siteSpecificBranchPairsName + strlen(siteSpecificBranchPairsName), "%s, ", branchPairNames);
            sprintf(siteSpecificBranchPairsIDs + strlen(siteSpecificBranchPairsIDs), "\"%s\", ", branchPairIDs);
        }else{
            sprintf(siteSpecificBranchPairs + strlen(siteSpecificBranchPairs), "%s ]", branchPairIDs);
            sprintf(siteSpecificBranchPairsName + strlen(siteSpecificBranchPairsName), "%s ]", branchPairNames);
            sprintf(siteSpecificBranchPairsIDs + strlen(siteSpecificBranchPairsIDs), "\"%s\" ]", branchPairIDs);
        }

        free(siteSpecificBP);
        free(branchPairIDs);
        free(branchPairNames);
    }
    if (numOfSelectedBranchPairs == 0) {
        strcat(siteSpecificBranchPairsIDs, "]");
    }


    siteSpecificBranchPairs = makeupDataOutput(siteSpecificBranchPairs, "siteSpecificBranchPairs");
    siteSpecificBranchPairsName = makeupDataOutput(siteSpecificBranchPairsName, "siteSpecificBranchPairsName");
    siteSpecificBranchPairsIDs = makeupDataOutput(siteSpecificBranchPairsIDs, "siteSpecificBranchPairsIDs");
    fprintf(dataFile, "%s;\n", siteSpecificBranchPairs);
    fprintf(dataFile, "%s;\n", siteSpecificBranchPairsName);
    fprintf(dataFile, "%s;\n", siteSpecificBranchPairsIDs);
    fclose(dataFile);

    free(siteSpecificMap);

    // generate five html files for data explore
    generateHTML(file, "UI/Template.html", NULL, NULL, 0);
    generateHTML(file, "UI/sheet-template.html", sheetFile, NULL, 0);
    generateHTML(file, "UI/siteSpecific-template.html", siteSpecificFile, selectedBranchPairs, numOfSelectedBranchPairs);
    generateHTML(file, "UI/rateVsDiversity-template.html", rateVsDiversityFile, NULL, 0);
    generateHTML(file, "UI/rateVsProbConvergence-template.html", rateVsProbConvergenceFile, selectedBranchPairs, numOfSelectedBranchPairs);

}

