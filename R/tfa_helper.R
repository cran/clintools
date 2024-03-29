#' @importFrom stats aggregate
#' @importFrom stats complete.cases
#' @importFrom stats approx
#' @importFrom stats fft
#' @importFrom stats sd
# ==== HELPERS ====

#Insert deleted rows based on missing n
Z.insert.deleted <- function(temp){
   del_n <- c(min(temp$n):max(temp$n))
   del_n <- del_n[-which(del_n %in% temp$n)]
   del_df <- as.data.frame(matrix(NA, ncol = ncol(temp), nrow = length(del_n)))
   colnames(del_df) <- colnames(temp)
   del_df$n <- del_n
   temp <- rbind(temp,del_df)
   temp <- temp[order(temp$n),]
   return(temp)
}

# ==== PEAK IDENTIFICATION ====
Z.peak_identification <- function(df, variables, deleter, freq){

   #find peaks (use - to identify minimum)
   Z.find_peaks <- function (x, freq){
      m <- freq/4
      shape <- diff(sign(diff(x, na.pad = FALSE)))
      pks <- sapply(which(shape < 0), FUN = function(i){
         z <- i - m + 1
         z <- ifelse(z > 0, z, 1)
         w <- i + m + 1
         w <- ifelse(w < length(x), w, length(x))
         if(all(x[c(z : i, (i + 2) : w)] <= x[i + 1])) return(i + 1) else return(numeric(0))
      })
      pks <- unlist(pks)
      pks
   }

   for(i in c(variables)){
      temp <- df[complete.cases(df[,c("t",i)]),]
      if(!is.null(deleter)){ temp <- Z.insert.deleted(temp) }
      rep <- 1
      peaks <- NA
      while(rep <= max(temp$n)){
         temp2 <- temp[temp$n >= rep & temp$n <= rep*15*freq,]
         temp2 <- temp2[!is.na(temp2$n),]
         if(any(is.na(temp2[,i]))){
            temp2[is.na(temp2[,i]),i] <- max(temp2[!is.na(temp2[,i]),i])
         }
         peaks <- c(peaks,temp2$t[Z.find_peaks(-temp2[[i]],freq)])
         rep <- rep+7.44*freq
      }
      peaks <- peaks[order(peaks)][!is.na(peaks)]
      rem_peaks <- NA
      for(j in c(1:(length(peaks)-1))){
         if(!is.na(peaks[j]) & !is.na(peaks[j+1])){
            if(abs(peaks[j]-peaks[j+1]) < 0.10){
               rem_peaks <- c(rem_peaks,j)
            }
         }
      }
      rem_peaks <- rem_peaks[!is.na(rem_peaks)]
      peaks <- peaks[-rem_peaks]
      #Find every cycle.
      temp <- temp[!is.na(temp$t),]
      temp$peaks <- 0
      temp$peaks[which(temp$t %in% peaks)] <- temp$abp[which(temp$t %in% peaks)]
      temp$cycle <- cumsum(c(0,as.numeric(diff(temp$peaks))!=0))
      temp$cycle[temp$cycle %% 2 == 1] <- temp$cycle[temp$cycle %% 2 == 1]-1
      temp$cycle <- temp$cycle/2
      #Insert mean value
      temp_mean <- aggregate(temp[[i]],by=list(temp$cycle),mean)
      colnames(temp_mean) <- c("cycle",paste0(i,"_cyclicmean"))
      temp_max <- aggregate(temp$t,by=list(temp$cycle),max)
      colnames(temp_max) <- c("cycle","t")
      temp_results <- merge(temp_max,temp_mean,by="cycle")
      colnames(temp_results)[which(colnames(temp_results) %in% "cycle")] <- paste0(i,"_cycle")

      df <- merge(df,temp_results,by="t",all.x = T)
   }

   return(df)
}

# ==== INTERPOLATION ====
Z.interpolation <- function(df, variables, interpolation, deleter){

   df <- Z.insert.deleted(df)

   for(i in c(variables)){
      temp <- df[complete.cases(df[,c("t",i)]),]
      if(!is.null(deleter)){
         temp2 <- temp[!is.na(temp$abp_cycle),c("n",paste0(i, "_cycle"))]
         temp2$start <- c(temp2$n[-length(temp2$n)],NA)
         temp2$end <- c(temp2$n[-1],NA)
         temp2 <- temp2[complete.cases(temp2),]
         temp2$num <- temp2$end - temp2$start
         temp2$real_num <- NA
         for(j in c(1:nrow(temp2))){
            temp2$real_num[j] <- nrow(temp[temp$n >= temp2$start[j] & temp$n < temp2$end[j],])
         }
         temp2$del_cycle[temp2$num != temp2$real_num] <- 1
         cycle <- temp2[[paste0(i, "_cycle")]][temp2$del_cycle == 1]
         cycle <- cycle[!is.na(cycle)]
         temp_ip <- unname(tapply(cycle, cumsum(c(1, diff(cycle)) != 1), range))
         df_ip <- NULL
         for(j in c(1:length(temp_ip))) df_ip <- as.data.frame(rbind(df_ip,t(as.data.frame(temp_ip[j]))))
         df_ip$start <- NA; df_ip$end <- NA; df_ip$interpol_length <- NA
         for(j in c(1:nrow(df_ip))){
            df_ip$start[j] <-  temp2$start[df_ip$V1[j] == temp2[[paste0(i, "_cycle")]]]
            df_ip$end[j] <-  temp2$end[df_ip$V2[j] == temp2[[paste0(i, "_cycle")]]]
            df_ip$length[j] <- df_ip$end[j]-df_ip$start[j]

            df_ip$interpol_length[j] <- mean(c(temp2$num[temp2[[paste0(i, "_cycle")]] == df_ip$V1[j]-1]*interpolation,
                   temp2$num[temp2[[paste0(i, "_cycle")]] == df_ip$V2[j]+1]*interpolation))
         }
         df_ip$interpolate <- (df_ip$interpol_length > df_ip$length)*1

         #flag interpolation in DF
         temp <- Z.insert.deleted(temp)
         for(j in c(1:nrow(df_ip))){
            temp$interpolate[temp$n > df_ip$start[j] & temp$n <= df_ip$end[j]] <- df_ip$interpolate[j]
         }
         temp[temp$interpolate == 1 & !is.na(temp$interpolate),paste0(i,"_cyclicmean")] <- NA
      }

      #interpolate beat-to-beat
      temp[[paste0(i,"_cyclicinterpol")]] <- approx(temp[[paste0(i,"_cyclicmean")]],
                                        xout = seq_along(temp[[paste0(i,"_cyclicmean")]]))$y
      temp[temp$interpolate == 0 & !is.na(temp$interpolate),paste0(i,"_cyclicinterpol")] <- NA
      df <- merge(df,temp[,c("n",paste0(i,"_cyclicinterpol"))],by="n")
   }
   return(df)
}

# ==== TFA FUNCTION ====
Z.TFA_func <- function(df, freq, output, vlf, lf, hf,
   detrend, spectral_smoothing, coherence2_thresholds,
   apply_coherence2_threshold, remove_negative_phase,
   remove_negative_phase_f_cutoff, normalize_ABP, normalize_CBFV,
   window_type, window_length, overlap, overlap_adjust, na_as_mean){

   #HELPER FUNCTIONS ----
      #Hanning function:
      Z.hanning_car <- function(M){
         w <- (1-cos(2*pi*(c(0:(M-1))/M)))/2
         return(w)
      }

      #Boxcar
      Z.boxcar  <- function(n)  {
         if (length(n) > 1 || n != floor(n) || n <= 0)
            stop("n must be an integer > 0")
         rep.int(1, n)
      }

      #DETREND

      Z.detrend <- function(x, tt = 'linear', bp = c()) {
         if (!is.numeric(x) && !is.complex(x))
            stop("'x' must be a numeric or complex vector or matrix.")
         trendType <- pmatch(tt, c('constant', 'linear'), nomatch = 0)

         if (is.vector(x))
            x <- as.matrix(x)
         n <- nrow(x)
         if (length(bp) > 0 && !all(bp %in% 1:n))
            stop("Breakpoints 'bp' must elements of 1:length(x).")

         if (trendType == 1) {  # 'constant'
            if (!is.null(bp))
               warning("Breakpoints not used for 'constant' trend type.")
            y <- x - matrix(1, n, 1) %*% apply(x, 2, mean)

         } else if (trendType == 2) {  # 'linear'
            bp <- sort(unique(c(0, c(bp), n-1)))
            lb <- length(bp) - 1

            a <- cbind(matrix(0, n, lb), matrix(1, n, 1))
            for (kb in 1:lb) {
               m <- n - bp[kb]
               a[(1:m) + bp[kb], kb] <- as.matrix(1:m)/m
            }
            y <- x - a %*% qr.solve(a, x)

         } else {
            stop("Trend type 'tt' must be 'constant' or 'linear'.")
         }

         return(y)
      }

      #ELEMTWISE MULTIPLICATION IN R
      #With 1 conj and one regular
      Z.elementwise_multi <- function(X,Y){
         df.x.real <- Re(X)
         df.x.imag <- Im(X)
         df.x.imag <- cbind(df.x.imag[,1],df.x.imag[,c(2:ncol(df.x.imag))]*-1)
         df.y.real <- Re(Y)
         df.y.imag <- Im(Y)
         df.y.imag <- cbind(df.y.imag[,1],df.y.imag[,c(2:ncol(df.y.imag))]*-1)

         df.x <- NULL
         df.y <- NULL
         for(i in c(1:ncol(X))){
            df.x <- cbind(df.x,complex(real=df.x.real[,i],imaginary=df.x.imag[,i]))
            df.y <- cbind(df.y,complex(real=df.y.real[,i],imaginary=df.y.imag[,i]))
         }

         results <- df.y
         for(i in c(1:nrow(df.x))){
            for(j in c(1:ncol(df.x))){
               results[i,j] <- df.x[i,j]*df.y[i,j]
            }
         }

         return(results)

      }

      #FILTERFILTER COMPLEX NUMBERS
      Z.filter.complex=function(x){complex(real=signal::filtfilt(h,1,Re(x)), imaginary=signal::filtfilt(h,1,Im(x)))}


   #TFA ----

      df <- df[,c("abp","mcav")]
      if(na_as_mean){
         df$abp[is.na(df$abp)] <- mean(df$abp,na.rm=T)
         df$mcav[is.na(df$mcav)] <- mean(df$mcav,na.rm=T)
      }else{
         df <- df[complete.cases(df),]
      }
      ABP <- df$abp
      CBFV <- df$mcav

      #Adjust ABP and CBFV
      output_var <- NULL
      output_var$abp_mean <- mean(ABP, na.rm=T)
      output_var$abp_sd <- sd(ABP, na.rm=T)
      output_var$cbfv_mean <- mean(CBFV, na.rm=T)
      output_var$cbfv_sd <- sd(CBFV, na.rm=T)

      if(detrend){
         ABP <- Z.detrend(ABP)
         CBFV <- Z.detrend(CBFV)
      }else{
         ABP <- ABP-mean(ABP, na.rm=T)
         CBFV <- CBFV-mean(CBFV, na.rm=T)
      }
      if(normalize_ABP) ABP <- (ABP/output_var$abp_mean)*100
      if(normalize_CBFV) CBFV <- (CBFV/output_var$cbfv_mean)*100

      #HANNING / BOXCAR
      window_l <- round(window_length*freq)
      if(window_type == "hanning") window <- Z.hanning_car(window_l)
      if(window_type == "boxcar") window <- Z.boxcar(window_l)

      #Overlapping
      if(overlap_adjust){
         L <- floor((length(ABP)-window_l)/(window_l*(1-overlap/100)))+1
         if(L>1){
            shift <- floor((length(ABP)-window_l)/(L-1))
            overlap <- (window_l-shift)/window_l*100;
            output_var$overlap <- overlap
         }
      }else{
            overlap=overlap;
      }

      overlap <- overlap/100;

      #FFT
      M_smooth <- spectral_smoothing

      if(length(window) == 1){
         M <- window
         window <- Z.boxcar(window_l)
      }else{
         M <- length(window)
      }

      shift <- round((1-overlap)*M)
      N <- length(ABP)

      X <- fft(ABP[1:M]*window)
      Y <- fft(CBFV[1:M]*window)
      L <- 1
      if(shift > 0){
         i_start <- 1+shift;
         while(i_start+M-1 <= N){
            X <- cbind(X,fft(ABP[i_start:(i_start+M-1)]*window,M))
            Y <- cbind(Y,fft(CBFV[i_start:(i_start+M-1)]*window,M))
            i_start <- i_start+shift;
            L <- L+1
         }
      }
      f <- c(0:(M-1))/M*freq

      #Phase/Gain/Coherence
      if(L == 1){
         Pxx <- as.numeric(X*Conj(X)/L/sum(window^2)/freq)
         Pyy <- as.numeric(Y*Conj(Y)/L/sum(window^2)/freq)
         Pxy <- Conj(X)*Y/L/sum(window^2)/freq
         coh <- Pxy/(abs(Pxx*Pyy))^0.5
      }else{
         Pxx <- as.numeric(rowSums(Z.elementwise_multi(X,Conj(X)))/L/sum(window^2)/freq)
         Pyy <- as.numeric(rowSums(Z.elementwise_multi(Y,Conj(Y)))/L/sum(window^2)/freq)
         Pxy <- rowSums(Z.elementwise_multi(Conj(X),Y))/L/sum(window^2)/freq
         coh <- Pxy/(abs(Pxx*Pyy))^0.5
      }

      if(M_smooth > 1){
         h <- rep(1,floor((M_smooth+1)/2))
         h <- h/sum(h)
         Pxx1 <- Pxx
         Pxx1[1] <- Pxx[2]
         Pyy1 <- Pyy
         Pyy1[1] <- Pyy[2]
         Pxy1 <- Pxy
         Pxy1[1] <- Pxy[2]

         Pxx1 <- signal::filtfilt(h,1,Pxx1)
         Pyy1 <- signal::filtfilt(h,1,Pyy1)
         Pxy1 <- Z.filter.complex(Pxy1)

         Pxx1[1] <- Pxx[1]
         Pxx <- Pxx1
         Pyy1[1] <- Pyy[1]
         Pyy <- Pyy1
         Pxy1[1] <- Pxy[1]
         Pxy <- Pxy1
      }
      H <- Pxy/Pxx
      C <- Pxy/(abs(Pxx*Pyy)^0.5)

      #Output and quality control
      output_var$H <- H
      output_var$C <- C
      output_var$f <- f
      output_var$Pxx <- Pxx
      output_var$Pyy <- Pyy
      output_var$Pxy <- Pxy
      output_var$no_windows <- L

      i=which(coherence2_thresholds[,1] %in% L)
      if(!is.numeric(i)){
         warning('No coherence threshold defined for the number of windows obtained - all frequencies will be included')
         coherence2_threshold=0;
      }else{
         coherence2_threshold <- coherence2_thresholds[i,2];
      }

      if(apply_coherence2_threshold){
         i <- which(abs(C)^2 < coherence2_threshold)
         H[i] <- NA
      }

      P <- atan2(Im(H), Re(H))

      if(remove_negative_phase){
         n <- which(f<remove_negative_phase_f_cutoff)
         k <- which(P[n]<0)
         if(length(k) != 0){
            P[n[k]] <- NA
         }
      }

      i <- which(f >= vlf[1] & f < vlf[2])
      output_var$vlf_gain <- mean(abs(H[i]),na.rm=T)
      output_var$vlf_phase <- mean(P[i],na.rm=T)/(2*pi)*360
      output_var$vlf_coh2 <- mean(abs(C[i])^2, na.rm=T)
      output_var$vlf_p_abp <- 2*sum(Pxx[i])*f[2]
      output_var$vlf_p_cbfv <- 2*sum(Pyy[i])*f[2]

      i <- which(f >= lf[1] & f < lf[2])
      output_var$lf_gain <- mean(abs(H[i]),na.rm=T)
      output_var$lf_phase <- mean(P[i],na.rm=T)/(2*pi)*360
      output_var$lf_coh2 <- mean(abs(C[i])^2, na.rm=T)
      output_var$lf_p_abp <- 2*sum(Pxx[i])*f[2]
      output_var$lf_p_cbfv <- 2*sum(Pyy[i])*f[2]

      i <- which(f >= hf[1] & f < hf[2])
      output_var$hf_gain <- mean(abs(H[i]),na.rm=T)
      output_var$hf_phase <- mean(P[i],na.rm=T)/(2*pi)*360
      output_var$hf_coh2 <- mean(abs(C[i])^2, na.rm=T)
      output_var$hf_p_abp <- 2*sum(Pxx[i])*f[2]
      output_var$hf_p_cbfv <- 2*sum(Pyy[i])*f[2]

      if(normalize_CBFV){
         output_var$vlf_gain_norm <- output_var$vlf_gain
         output_var$lf_gain_norm <- output_var$lf_gain
         output_var$hf_gain_norm <- output_var$hf_gain
         output_var$vlf_gain_not_norm <- output_var$vlf_gain*output_var$cbfv_mean/100
         output_var$lf_gain_not_norm <- output_var$lf_gain*output_var$cbfv_mean/100
         output_var$hf_gain_not_norm <- output_var$hf_gain*output_var$cbfv_mean/100
      }else{
         output_var$vlf_gain_not_norm <- output_var$vlf_gain
         output_var$lf_gain_not_norm <- output_var$lf_gain
         output_var$hf_gain_not_norm <- output_var$hf_gain
         output_var$vlf_gain_norm <- output_var$vlf_gain/output_var$cbfv_mean*100
         output_var$lf_gain_norm <- output_var$lf_gain/output_var$cbfv_mean*100
         output_var$hf_gain_norm <- output_var$hf_gain/output_var$cbfv_mean*100
      }


      results <- round(rbind(
         cbind(output_var$vlf_p_abp,output_var$lf_p_abp,output_var$hf_p_abp),
         cbind(output_var$vlf_p_cbfv,output_var$lf_p_cbfv,output_var$hf_p_cbfv),
         cbind(output_var$vlf_coh2,output_var$lf_coh2,output_var$hf_coh2),
         cbind(output_var$vlf_gain_not_norm,output_var$lf_gain_not_norm,output_var$hf_gain_not_norm),
         cbind(output_var$vlf_gain_norm,output_var$lf_gain_norm,output_var$hf_gain_norm),
         cbind(output_var$vlf_phase,output_var$lf_phase,output_var$hf_phase)
      ),digits=2)

      colnames(results) <- c("VLF","LF","HF")
      results <- cbind(c("abp_power","cbfv_power","coherence", "gain_not_normal", "gain_normal","phase"),results)
      results <- as.data.frame(results)
      colnames(results)[1] <- "variable"

      #PLOT output
      plot <- cbind(f,abs(output_var$H),atan2(Im(output_var$H), Re(output_var$H))/(2*pi)*360,abs(C)^2)
      colnames(plot) <- c("freq","gain","phase","coherence")
      plot <- as.data.frame(plot)

      #LONG OUTPUT
      long_df <- NULL
      for(i in c(1:nrow(results))){
         for(j in c(2:ncol(results))){
            long_df <- rbind(long_df,c(tolower(colnames(results)[j]),results[i,1],results[i,j]))
         }
      }
      long_df <- as.data.frame(long_df)
      colnames(long_df) <- c("interval","variable","values")
      long_df <- long_df[order(long_df$interval,long_df$variable),]
      long_df$values <- as.numeric(long_df$values)
      rownames(long_df) <- c(1:nrow(long_df))

      if(output == "raw") return(output_var)
      if(output == "plot") return(plot)
      if(output == "long") return(long_df)
      if(output != "raw" & output != "plot" & output != "long") return(results)
}




