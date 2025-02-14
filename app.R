# A lightweight ShinyApp for coding of text data for qualitative analysis
# QualCA (pronounced like Quokka; not yet final)
# Written by William Ngiam
# Started on Sept 15 2024
# Version 0.1.5 (Jan 16 2024)
#
# Motivated by the ANTIQUES project
#
# Wishlist
# Take in various corpus input files
# Edit text viewer to show all relevant information
# Add codebook, codes, extracts - have all linked and viewable.
# Apply specific colours for the code
# Collaborative coding <- maybe a google sheet that contains code/extracts...
# Floating menus?
# Dealing with line breaks
# Audit trail page - running commentary/notes
# Automatic sending to OSF project
# "Stats" tab <- Number of extracts, number of documents coded
#
# Glossary
# Corpus: The body of text to be qualitatively analysed
# Document: Each item that makes up the corpus
# Extract: The harvested section of text that is coded
#
# --- #

# Load required packages
library(tools)
#library(pdftools)
library(shiny)
library(shinydashboard)
library(shinyalert)
library(shinyjs)
library(shinyjqui)
library(DT) # for data presentation purposes
library(tibble)
library(dplyr) # for data wrangling
library(readr)
library(stringr) # for handling strings
library(markdown)
library(sortable) # For list sorting
#library(officer) # Uncomment if want to load in word documents locally

# Workaround for Chromium Issue 468227
# Copied from https://shinylive.io/r/examples/#r-file-download
downloadButton <- function(...) {
  tag <- shiny::downloadButton(...)
  tag$attribs$download <- NULL
  tag
}

### UI ###
ui <- dashboardPage(
  dashboardHeader(title = "quokka - a qualitative coding app",
                  titleWidth = 350),
  dashboardSidebar(
    width = 350,
    fluidPage(HTML("<h3>Upload Files</h3>")),
    fileInput(
      "corpusFile",
      "Load Corpus",
      accept = c(
        "text/csv",
        "text/comma-separated-values,text/plain",
        ".csv",
        ".pdf",
        ".docx"
      )
    ),
    # Upload the corpus of documents to-be-analysed
    uiOutput("documentTextSelector"),
    fileInput(
      "codebookFile",
      "Load Codebook",
      accept = c("text/csv", "text/comma-separated-values,text/plain", ".csv")
    ),
    # Upload any existing codebook
    uiOutput("codebookSelector"),
    fluidPage(HTML("<h3>Download Codebook</h3>")),
    fluidPage(
      downloadButton("downloadData",
                     label = "Download Codebook",
                     style = "color: black")
    ),
    fluidPage(HTML("<br><h3>Pages</h3>")),
    sidebarMenu(
      id = "sbMenu",
      menuItem("Home", tabName = "home", icon = icon("home")),
      menuItem("Coding", tabName = "coder", icon = icon("highlighter")),
      menuItem(
        "Reviewing",
        tabName = "reviewer",
        icon = icon("magnifying-glass")
      ),
      menuItem(
        "Sorting",
        tabName = "themes",
        icon = icon("layer-group")
      )
    ),
    fluidPage(HTML("<br>Created by William Ngiam"))
  ),
  dashboardBody(tabItems(
    # The home tab
    tabItem(tabName = "home",
            useShinyjs(), #Initialize shinyjs
            fluidPage(includeHTML("home_text.html"))),
    # The coding tab
    tabItem(
      tabName = "coder",
      useShinyjs(),
      # Initialize shinyjs
      fluidRow(
        jqui_resizable(
          box(
            title = "Document Viewer",
            width = 6,
            solidHeader = TRUE,
            status = "primary",
            fluidPage(fluidRow(
              column(
                width = 5,
                numericInput(
                  inputId = "documentID_viewer",
                  label = "Document #",
                  value = "currentDocumentID"
                )
              ),
              column(
                width = 5,
                offset = 1,
                HTML("<strong>Document Navigation </strong><br>"),
                actionButton("prevDocument", "Previous", icon = icon("arrow-left")),
                actionButton("nextDocument", "Next", icon = icon("arrow-right"))
              )
            )),
            bootstrapPage(
              tags$style("#textDisplay {
                        overflow-y: auto;
                        max-height: 55vh;
                    }"),
              uiOutput("textDisplay"),
              tags$script(
                '
              function getSelectionText() {
                var text = "";
                if (window.getSelection) {
                  text = window.getSelection().toString();
                } else if (document.selection) {
                  text = document.selection.createRange().text;
                }
                return text;
              }
              document.onmouseup = document.onkeyup = document.onselectionchange = function() {
                  var selection = getSelectionText();
                  Shiny.onInputChange("extract",selection);
              };
              '
              )
            )
          )
        ),
        box(
          title = "Quick Look",
          width = 6,
          solidHeader = TRUE,
          status = "primary",
          fluidPage(DTOutput("counterTable"))
        ),
      ),
      fluidRow(
        box(
          title = "Research Question(s)",
          width = 12,
          solidHeader = TRUE,
          status = "primary",
          textAreaInput("text",
                        "Enter your research question(s) below")
        )
      ),
      fluidRow(
        box(
          title = "Codebook",
          width = 12,
          solidHeader = TRUE,
          status = "primary",
          actionButton(
            "addSelectedText",
            "Add Selected Text as Extract",
            icon = icon("pencil")
          ),
          actionButton("deleteExtract", "Delete Extract from Codebook", icon = icon("trash")),
          actionButton("addColumn", "Add Column to Codebook", icon = icon("plus")),
          actionButton("removeColumn", "Remove Column from Codebook", icon = icon("minus")),
          HTML("<br><br>"),
          DTOutput("codebookTable")
        )
      )
    ),
    tabItem(tabName = "reviewer",
            fluidRow(
              box(
                title = "Codebook",
                width = 3,
                solidHeader = TRUE,
                status = "primary",
                DTOutput("codesTable")
              ),
              box(
                title = "Extracts",
                width = 9,
                solidHeader = TRUE,
                status = "primary",
                DTOutput("reviewTable")
              )
            ),
            fluidRow(
              box(
                title = "Document Review",
                width = 12,
                solidHeader = TRUE,
                status = "primary",
                uiOutput("reviewDocumentText")
              )
            )),
    tabItem(tabName = "themes",
            fluidRow(
              box(
                title = "Themes",
                width = 12,
                solidHeader = TRUE,
                status = "primary",
                actionButton("addTheme", "Create a new theme", icon = icon("plus")),
                downloadButton("downloadThemes", "Download themes", icon = icon("floppy-disk")),
                uiOutput("uniqueCodes")
              )
            ))
  ))
)

### SERVER ###
server <- function(input, output, session) {
  # Reactive values to store data and codebook
  values <- reactiveValues(
    corpus = NULL,
    # the text data to be analysed
    documentTextColumn = NULL,
    # the column which contains document text
    selectedText = NULL,
    codebook = tibble(
      Theme = as.character(),
      Code = as.character(),
      Extract = as.character(),
      Document_ID = as.numeric(),
      Timestamp = as.character()
    ),
    counter = data.frame(),
    currentDocumentIndex = 1,
    nDocuments = 1,
    selection = NULL,
    thisExtract = NULL,
    nThemes = 2 # for sorting into themes
  )
  
  ### FUNCTIONS ###
  # Update text display based on currentDocumentIndex and documentTextColumn
  updateTextDisplay <- function() {
    req(values$corpus, values$documentTextColumn)
    text <-
      values$corpus[[values$documentTextColumn]][values$currentDocumentIndex]
    #text <- sub("<span*/span>","",text) # Remove any leftover HTML
    text <-
      gsub(pattern = "\n", replacement = "", text) # Remove line breaks because they "break" the app...
    text <- gsub(pattern = "\\s+", replacement = " ", text)
    #text <- gsub(pattern = "\"", replacement = "'", text) # Replace double quotation marks with single ones.
    textLength <- str_length(text)
    
    # Add highlights here by adding HTML tags to text
    # Retrieve document ID
    currentDoc <- values$currentDocumentIndex
    
    # Get saved extracts for document ID
    currentExtracts <- values$codebook %>%
      dplyr::filter(Document_ID == currentDoc)
    oldStrings = currentExtracts$Extract
    
    if (length(oldStrings) > 0) {
      # Detect where extracts start and finish in text
      stringLocs <-
        as.data.frame(str_locate(text, paste0("\\Q", oldStrings, "\\E")))
      stringLocs <-
        na.omit(stringLocs) # omit NA where matches don't work with special characters
      addedStringStart = last(stringLocs$start)
      # Sort these locations by their starting order
      stringLocs <- stringLocs %>%
        arrange(start)
      
      # If more than one string, check for overlaps (leetcode 56)
      if (length(oldStrings) > 1) {
        # Write the first interval to start result
        reducedStrings <- tibble(start = as.numeric(),
                                 end = as.numeric()) %>%
          tibble::add_row(
            start = head(stringLocs$start, n = 1),
            end = head(stringLocs$end, n = 1)
          )
        
        for (i in 1:nrow(stringLocs)) {
          # Retrieve the next interval
          thisStringStart <- stringLocs$start[i]
          thisStringEnd <- stringLocs$end[i]
          # Check for overlap
          if (between(
            thisStringStart,
            tail(reducedStrings, n = 1)$start,
            tail(reducedStrings, n = 1)$end
          )) {
            # If overlap, change value of interval
            reducedStrings[nrow(reducedStrings), ncol(reducedStrings)] = max(thisStringEnd, tail(reducedStrings, n = 1)$end)
          }
          else {
            # If no overlap, add the interval
            reducedStrings <- reducedStrings %>%
              add_row(start = thisStringStart, end = thisStringEnd)
          }
        }
        # Arrange in descending order for inserting HTML
        stringLocs <- reducedStrings %>%
          arrange(desc(start))
      }
      
      for (i in 1:nrow(stringLocs)) {
        # Get start and end
        stringStart <- stringLocs$start[i]
        stringEnd <- stringLocs$end[i]
        theString <- str_sub(text, stringStart, stringEnd)
        # Get string
        if (stringStart == addedStringStart) {
          str_sub(text, stringStart, stringEnd) <-
            paste0(
              "<span id=\"lastString\" style=\"background-color: powderblue\">",
              theString,
              "</span>"
            )
        } else {
          str_sub(text, stringStart, stringEnd) <-
            paste0("<span style=\"background-color: powderblue\">",
                   theString,
                   "</span>")
        }
      }
    }
    
    # Hope it works
    if (textLength >= 600) {
      output$textDisplay <- renderUI({
        tags$div(
          id = "textDisplay",
          tags$p(HTML(text), id = "currentText", style = "font-size: 20px"),
          tags$script('
                      lastString.scrollIntoView();
                      ')
        )
      })
    } else {
      output$textDisplay <- renderUI({
        tags$div(id = "textDisplay",
                 tags$p(HTML(text), id = "currentText", style = "font-size: 20px"))
      })
    }
  }
  
  # Update document viewer ID number
  updateDocumentID <- function() {
    updateNumericInput(
      session,
      inputId = "documentID_viewer",
      value = values$currentDocumentIndex,
      max = values$nDocuments
    )
  }
  
  # Save codebook locally
  saveCodebook <- function() {
    req(values$codebook)
    write.csv(values$codebook, "temp_codebook.csv", row.names = FALSE)
  }
  
  # Render codebook
  renderCodebook <- function() {
    output$codebookTable <- renderDT({
      idColNum <- which(colnames(values$codebook) == "Timestamp")
      datatable(
        values$codebook,
        options = list(order = list(idColNum - 1, 'desc')),
        editable = TRUE,
        rownames = FALSE
      )
    })
  }
  
  # Render code counter
  renderCounter <- function() {
    values$counter <- values$codebook %>%
      count(Code, name = "Instances")
    
    output$counterTable <- renderDT({
      datatable(
        values$counter,
        editable = list(target = "cell",
                        disable = list(columns = 1)),
        rownames = FALSE
      )
    })
    
    output$codesTable <- renderDT({
      datatable(
        values$counter,
        editable = list(target = "cell",
                        disable = list(columns = 1)),
        rownames = FALSE
      )
    })
  }
  
  ### UPLOADING DATA ###
  # Load corpus CSV file and update column selector
  observeEvent(input$corpusFile, {
    req(input$corpusFile)
    if (file_ext(input$corpusFile$datapath) == "csv") {
      values$corpus <-
        read.csv(input$corpusFile$datapath, stringsAsFactors = FALSE)
    } else if (file_ext(input$corpusFile$datapath) == "txt") {
      values$corpus <-
        read.delim(input$corpusFile$datapath,
                   header = FALSE,
                   sep = "\n")
    } else if (file_ext(input$corpusFile$datapath) == "pdf") {
      pdfDocumentText <- pdf_text(input$corpusFile$datapath)
      values$corpus <- tibble(text = pdfDocumentText)
    } else if (file_ext(input$corpusFile$datapath) == "docx") {
      doc <- read_docx(input$corpusFile$datapath)
      docContent <- docx_summary(doc) %>%
        filter(text != "")
      
      values$corpus <-
        tibble(text = paste(docContent$text, collapse = ""))
      
    }
    colnames <- colnames(values$corpus)
    values$documentTextColumn <-
      colnames[1]  # Default to the first column
    values$currentDocumentIndex <- 1  # Reset index on new file load
    values$nDocuments <-
      nrow(values$corpus) # Get number of documents
    
    output$documentTextSelector <- renderUI({
      req(values$corpus)
      selectInput(
        "documentTextColumn",
        "Select Text Column",
        choices = colnames,
        selected = values$documentTextColumn
      )
    })
    
    updateTextDisplay()
    renderCodebook()
    renderCounter()
    
    updateSelectInput(
      session,
      "codebookSelector",
      choices = values$codebook$Theme,
      selected = NULL
    )
  })
  
  # Update codebook on upload
  observeEvent(input$codebookFile, {
    req(input$codebookFile)
    values$codebook <-
      read.csv(input$codebookFile$datapath, stringsAsFactors = FALSE)
    colnames <- colnames(values$codebook)
    renderCodebook()
    renderCounter()
    updateTextDisplay()
  })
  
  
  ## DOCUMENT NAVIGATION ##
  # Update display after document text column is selected
  observeEvent(input$documentTextColumn, {
    values$documentTextColumn <- input$documentTextColumn
    updateTextDisplay()
  })
  
  # Updated display after document ID is scrolled
  observeEvent(input$documentID_viewer, {
    req(values$corpus)
    if (input$documentID_viewer > nrow(values$corpus)) {
      values$currentDocumentIndex <- nrow(values$corpus)
      updateTextDisplay()
    } else if (values$currentDocumentIndex > 1) {
      values$currentDocumentIndex <- input$documentID_viewer
      # Updated text display
      updateTextDisplay()
    }
  })
  
  # Action button for previous document
  observeEvent(input$prevDocument, {
    req(values$corpus)
    if (values$currentDocumentIndex > 1) {
      values$currentDocumentIndex <- values$currentDocumentIndex - 1
      
      # Updated text display
      updateDocumentID()
      updateTextDisplay()
      
    }
  })
  
  # Action button for next document
  observeEvent(input$nextDocument, {
    req(values$corpus)
    if (values$currentDocumentIndex < nrow(values$corpus)) {
      values$currentDocumentIndex <- values$currentDocumentIndex + 1
      updateDocumentID()
      updateTextDisplay()
    }
  })
  
  ## CODEBOOK ACTIONS ##
  # Save after any edits to the codebook
  observeEvent(input$codebookTable_cell_edit, {
    values$codebook <-
      editData(values$codebook,
               input$codebookTable_cell_edit,
               rownames = FALSE,
               'codebookTable')
    saveCodebook()
    renderCounter()
    updateTextDisplay()
  })
  
  # Add selected text as extract
  observeEvent(input$addSelectedText, {
    req(values$codebook, input$extract)
    selectedText <-
      input$extract # Highlighted text within document to-be-extracted
    
    # Detect any selected rows
    #    if (nrow(values$counter) > 0) {
    if (!is.null(input$counterTable_rows_selected)) {
      selectedRow <- input$counterTable_rows_selected
      allCodes <- values$counter$Code
      selectedCode <- allCodes[selectedRow]
    } else {
      selectedCode = ""
    }
    #    } else {
    #       selectedCode = ""
    #   }
    
    # Append the selected text to codebook as extract
    values$codebook <- values$codebook %>%
      add_row(
        Theme = "",
        Code = selectedCode,
        Extract = selectedText,
        Document_ID = values$currentDocumentIndex,
        Timestamp = as.character(Sys.time())
      )
    
    renderCodebook()
    renderCounter()
    updateTextDisplay()
  })
  
  # Delete extract from codebook
  observeEvent(input$deleteExtract, {
    req(input$codebookTable_rows_selected)
    whichRow <-
      input$codebookTable_rows_selected # highlighted rows in codebook
    values$codebook <- values$codebook[-whichRow,]
    renderCodebook()
    renderCounter()
    updateTextDisplay()
  })
  
  # Get column name in response to add button
  observeEvent(input$addColumn, {
    req(values$codebook)
    showModal(modalDialog(
      textInput(
        "colName",
        "Name of new column in codebook:",
        value = "Notes",
        placeholder = "Notes"
      ),
      footer = tagList(modalButton("Cancel"),
                       actionButton("addCol", "OK"))
    ))
  })
  
  # Add column to codebook after getting name
  observeEvent(input$addCol, {
    req(values$codebook)
    newColName = input$colName
    if (newColName == "") {
      newColName = "New column"
    }
    values$codebook <- values$codebook %>%
      mutate(newColumn = as.character("")) %>%
      rename_with(~ newColName, newColumn)
    
    removeModal()
    renderCodebook()
  })
  
  # Remove column name in response to add button
  observeEvent(input$removeColumn, {
    req(values$codebook)
    showModal(modalDialog(
      selectInput(
        "minusCol",
        "Select which column to remove",
        choices = colnames(values$codebook)
      ),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("minusColButton", "OK")
      )
    ))
  })
  
  # Remove column to codebook after getting selection
  observeEvent(input$minusColButton, {
    req(values$codebook)
    minusColName = input$minusCol
    values$codebook <- values$codebook %>%
      select(-matches(paste0(minusColName)))
    
    removeModal()
    renderCodebook()
  })
  
  # Save and apply rewording of code
  observeEvent(input$counterTable_cell_edit, {
    # Update counter
    values$counter <-
      editData(values$counter,
               input$counterTable_cell_edit,
               rownames = FALSE,
               'counterTable')
    
    ## Get previous code value
    # Recreate previous counter
    oldCounterTable <- values$codebook %>%
      count(Code, name = "Instances")
    
    # Retrieve old Code
    info = input$counterTable_cell_clicked
    changeRow = info$row
    changeCol = info$col
    oldValue = info$value
    
    # Retrieve new Code
    new_info = input$counterTable_cell_edit
    newValue = new_info$value
    
    # Replace strings in codebook
    values$codebook$Code[values$codebook$Code == oldValue] <-
      as.character(newValue)
    renderCodebook()
  })
  
  # Download handler for the codebook
  output$downloadData <- downloadHandler(
    filename = function() {
      paste("codebook-", Sys.Date(), ".csv", sep = "")
    },
    content = function(file) {
      write.csv(values$codebook, file, row.names = FALSE)
    }
  )
  
  ## EXTRACT VIEWER (REVIEW TAB)
  # Display all extracts related to a code
  findExtracts <- function() {
    # Get selected code
    whichRow <- input$codesTable_rows_selected
    allCodes <- values$counter$Code
    selectedCode <- allCodes[whichRow]
    
    # Filter for relevant extracts
    relevantExtracts <- values$codebook %>%
      dplyr::filter(grepl(paste(selectedCode,
                                collapse = "|"),
                          Code)) %>%
      select(Extract)
    
    # Organise the display to show all extracts.
    output$reviewTable <- renderDT({
      datatable(relevantExtracts,
                rownames = FALSE)
    })
  }
  
  showDocument <- function() {
    req(input$codesTable_rows_selected,
        input$reviewTable_rows_selected)
    # Get selected codes
    whichRow <- input$codesTable_rows_selected
    allCodes <- values$counter$Code
    selectedCode <- allCodes[whichRow]
    
    # Get selected extract
    whichExtractRow <- input$reviewTable_rows_selected
    whichExtractRow <-
      max(whichExtractRow) # in case multiple selected.
    
    # Filter for data
    documentData <- values$codebook %>%
      dplyr::filter(grepl(paste(selectedCode,
                                collapse = "|"),
                          Code)) %>%
      select(Document_ID, Extract)
    
    # Find which document
    allDocs <- documentData$Document_ID
    selectedDocument <- allDocs[whichExtractRow]
    documentText <-
      values$corpus[[values$documentTextColumn]][selectedDocument]
    
    # Find exact extract
    allExtracts <- documentData$Extract
    selectedExtract <- allExtracts[whichExtractRow]
    
    # Clean document text
    documentText <-
      gsub(pattern = "\n", replacement = "", documentText) # Remove line breaks because they "break" the app...
    documentText <-
      gsub(pattern = "\\s+", replacement = " ", documentText)
    
    # Find location of matches
    stringEnds <-
      as.data.frame(str_locate(documentText, paste0("\\Q", selectedExtract, "\\E")))
    
    # Replace with highlight HTML
    stringBegin <- stringEnds$start
    stringFinish <- stringEnds$end
    str_sub(documentText, stringBegin, stringFinish) <-
      paste0("<span style=\"background-color: powderblue\">",
             selectedExtract,
             "</span>")
    
    output$reviewDocumentText <- renderUI({
      tags$div(id = "reviewDocumentText",
               tags$p(HTML(documentText), id = "currentDocumentText", style = "font-size: 20px"))
    })
    
  }
  
  # If reviewing tab selected
  observeEvent(input$codesTable_rows_selected, {
    findExtracts()
  })
  
  observeEvent(input$reviewTable_rows_selected, {
    req(input$codesTable_rows_selected)
    showDocument()
  })
  
  ## SORTING CODES INTO THEMES
  ## Probably need a build UI function, and then a render function.
  ## Also need an output function.
  
  # Define reactive value for the codes organised into themes (bucket_list)
  themeData <- reactiveValues(themeList = list(),
                              themeName = list())
  
  # Load codes in initially
  loadInCodes <- function() {
    req(values$counter)
    if (!is.null(values$counter$Code)) {
      allCodes <- values$counter$Code
      themeData$themeList$rank_list_1 <- allCodes
      themeData$themeList$rank_list_2 <- list()
    }
  }
  
  # Render after clicking on the sidebar menu the first time
  observeEvent(input$sbMenu, {
    if (input$sbMenu == "themes" && length(themeData$themeList) < 1) {
      loadInCodes()
    }
  })
  
  # Save reactive values for codes organised into themes
  saveThemeData <- function() {
    themeData$themeList <-
      input$codesToThemes # Saves in the current list
  }
  
  observeEvent(input$addTheme, {
    req(input$codesToThemes)
    saveThemeData()
    themeData$themeList[length(themeData$themeList) + 1] <-
      list(NULL)
    updateCodesUI()
  })
  
  observeEvent(input$sbMenu, {
    # Define rank list for bucket
    if (length(themeData$themeList) > 0) {
      buildRankList <-
        lapply(seq(length(themeData$themeList)), function(x) {
          if (x <= length(themeData$themeList)) {
            add_rank_list(
              text = "",
              labels = themeData$themeList[[x]],
              input_id = paste0("rank_list_", x)
            )
          } else {
            add_rank_list(
              text = "",
              labels = list(),
              input_id = paste0("rank_list_", x)
            )
          }
        })
      
      # Render theme UI
      renderCodesUI <- function() {
        output$uniqueCodes <- renderUI({
          do.call("bucket_list", args = c(
            list(
              header = "",
              group_name = "codesToThemes",
              orientation = "horizontal"
            ),
            buildRankList
          ))
        })
      }
      
      renderCodesUI()
      saveThemeData()
    }
  })
  
  ## Function for rendering codes UI
  # Define rank list for bucket
  updateCodesUI <- function() {
    if (length(themeData$themeList) > 0) {
      buildRankList <-
        lapply(seq(length(themeData$themeList)), function(x) {
          if (x <= length(themeData$themeList)) {
            add_rank_list(
              text = "",
              labels = themeData$themeList[[x]],
              input_id = paste0("rank_list_", x)
            )
          } else {
            add_rank_list(
              text = "",
              labels = list(),
              input_id = paste0("rank_list_", x)
            )
          }
        })
      
      # Render theme UI
      renderCodesUI <- function() {
        output$uniqueCodes <- renderUI({
          do.call("bucket_list", args = c(
            list(
              header = "",
              group_name = "codesToThemes",
              orientation = "horizontal"
            ),
            buildRankList
          ))
        })
      }
      
      renderCodesUI()
    }
  }
  
  output$downloadThemes <- downloadHandler(
    filename = function() {
      paste0("themes-", Sys.Date(), ".csv")
    },
    content = function(file) {
      themeData$themeList <- input$codesToThemes
      # Find max length of lists
      maxLength <- max(lengths(themeData$themeList))
      # Convert themes into dataframe
      themesOut <-
        do.call(rbind, lapply(themeData$themeList, `[`, seq_len(maxLength)))
      themesOut <- t(themesOut)
      # Send to download handler
      write.csv(themesOut, file)
    }
  )
  
}

shinyApp(ui, server)