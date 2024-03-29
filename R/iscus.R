# ==== DOCUMENTATION ====

#' ISCUSFlex-values to dataframe  (iscus)
#'
#' `iscus()` is a function which converts XML files extracted
#' from the Microdialysis-apparatur of ISCUSFlex apparatus to a dataframe.
#'
#' @name iscus
#'
#' @usage iscus(filename)
#'
#' @param filename path to the XML-file with the measurements
#'
#' @return Returns a dataframe with the measurements.
#'
#' @examples
#'  \dontrun{
#'    iscus("C:/ISCUSfiles/7888e844-1c7a-40af-a3f2-3bb27a8dd9e5.xml")
#'  }
#'
#' @importFrom xml2 read_xml
#' @importFrom xml2 xml_text
#' @importFrom xml2 xml_find_all
#' @importFrom xml2 xml_attr
#' @importFrom xml2 xml_name
#' @importFrom xml2 xml_children
#' @importFrom xml2 as_list
#' @export
#
# ==== FUNCTION ====

iscus <- function(filename){

   #Import file
   xmlobj <- read_xml(filename)
   vars <- NULL

   #Extract as text
   extract_vars <- function(x,y){
      z <- xml_text(xml_find_all(x, y))
      z[identical(z,character(0))] <- ""
      return(z)
   }

   #General variables
   vars$UniqueID <- extract_vars(xmlobj, ".//d1:UniqueID")
   vars$Machine <- extract_vars(xmlobj, ".//d1:Machine")
   vars$AdmissionDate <- extract_vars(xmlobj, ".//d1:AdmissionDate")
   vars$AdmissionEndDate <- extract_vars(xmlobj, ".//d1:AdmissionEndDate")
   vars$AdmissionNote <- extract_vars(xmlobj, ".//d1:AdmissionNote")

   #Patient
   vars$PatientID <- extract_vars(xmlobj, ".//d1:Patient/d1:PatientID")
   vars$FirstName <- extract_vars(xmlobj, ".//d1:Patient/d1:FirstName")
   vars$LastName <- extract_vars(xmlobj, ".//d1:Patient/d1:LastName")

   #Numbers
   xml_rec <- xml_find_all( xmlobj, ".//d1:Recording" )

   df_results <- NULL

   if(length(xml_rec) == 0) return(df_results)

   rec <- NULL
   for(i in c(1:length(xml_rec))){

      rec$CatheterLocation <- xml_text(xml_find_all(xml_rec[i],".//d1:CatheterLocation"))

      rec$AnalyteCode <- extract_vars(xml_rec[i],".//d1:AnalyteCode")
      rec$Start <- extract_vars(xml_rec[i],".//d1:Start")
      rec$Unit <- xml_attr(xml_rec[i], "Unit" )

      rec$no <- sum(1*(xml_name(xml_children(xml_rec[i])) == "Measurement"))
      rec$var <- unique(xml_name(xml_children(xml_find_all(xml_rec, ".//d1:Measurement"))))

      measures_df <- data.frame(matrix(ncol=length(rec$var)))
      colnames(measures_df) <- rec$var
      if(rec$no != 0){
         for(j in c(1:rec$no)){

            measures_vars <- NULL
            xml_measure <- xml_find_all(xml_rec[i],".//d1:Measurement")[j]
            test <- as_list(xml_measure)[[1]]
            test_df <- data.frame(test)
            colnames(test_df) <- names(test)

            measures_df <- merge(measures_df, test_df, all=T)

         }
      }
      temp_df <- cbind(rec$CatheterLocation, rec$Start, rec$AnalyteCode, rec$Unit, measures_df)
      colnames(temp_df)[1:4] <- c("CatheterLocation","Start","AnalyteCode","Unit")

      df_results <- rbind(df_results,temp_df)
   }

   df_results <- cbind(vars$PatientID, vars$FirstName, vars$LastName,
                       vars$UniqueID,vars$Machine,vars$AdmissionDate,vars$AdmissionEndDate,
                       vars$AdmissionNote,
                       df_results)
   colnames(df_results) <- gsub("vars\\$","",colnames(df_results))

   do_date <- function(x){
      x <- as.POSIXct(gsub("T"," ",x), format="%Y-%m-%d %H:%M:%S")
   }

   df_results$AdmissionDate <- do_date(df_results$AdmissionDate)
   df_results$AdmissionEndDate <- do_date(df_results$AdmissionEndDate)
   df_results$Start <- do_date(df_results$Start)
   df_results$TimeStamp <- do_date(df_results$TimeStamp)

   if(is.null(df_results$Status)){ df_results$Status <- NA }
   df_results <- df_results[,!is.na(colnames(df_results))]

   rownames(df_results) <- c(1:nrow(df_results))

   return(df_results)

}
