#include <TFile.h>
#include <TH2D.h>
#include <TH1D.h>
#include <TCanvas.h>
#include <TGraph.h>
#include <fstream>
#include <iostream>
#include <vector>

#define PILEUP_THR 100 // - 0.015 V
#define MIN_PEAK_SEPARATION 10 // Minimum samples between peaks

#define POLARITY 1
#define DATA_SIZE 128
#define BIN_WIDTH 8

#define BL_CUT 10

#define PSD_BIN 10

const int H_TRACE_SAMPLES = DATA_SIZE; // 128
const double V_MIN = -8192, V_MAX = 8192; //500
const int V_NBINS = V_MAX - V_MIN;
const int H_AMPL_NBINS = 8192;//8192
const int H_INT_NBINS = 500;//500
const double H_INT_MAX[2] = {200000, 60000};

const int H_PSD_NBINS = 1000;

void CutBaseLine(int16_t* data) {
    int16_t FIRST_BL_MEAN = 0, BL_MEAN = 0;
    for (int i = 0; i < BL_CUT; i++){
		//printf("bin[%i] data[%i] \n", i, data[i]);
        FIRST_BL_MEAN += data[i];
	}	
    FIRST_BL_MEAN /= BL_CUT;

    BL_MEAN = FIRST_BL_MEAN;
    for (int i = 0; i < DATA_SIZE; i++)
        data[i] -= BL_MEAN;
}

void CalcParams(int16_t *arr, int *m_stamp, int *ampl, double *integral, float *psd_val) {
    int max_ampl = arr[0] * POLARITY;
    int max_idx = 0;
    double total_integral = 0;
    //double pre_max_sum = 0;

    for (int i = 0; i < DATA_SIZE; i++) {
        int val = arr[i] * POLARITY;
        total_integral += val;
        if (val > max_ampl) {
            max_ampl = val;
            max_idx = i;
            //pre_max_sum = total_integral - val;
        }
    }

    double Qs = 0.0;
	double Ql = 0.0;
    int psd_end = max_idx + PSD_BIN;
    //if (psd_end >= DATA_SIZE) psd_end = DATA_SIZE - 1;
    for (int i = max_idx; i <= psd_end; i++) 
        Qs += arr[i] * POLARITY;
    
	
	for (int i = max_idx; i < DATA_SIZE; i++){ 
        Ql += arr[i] * POLARITY;
		//total_integral += val;
	}	

    *ampl = max_ampl;
    *m_stamp = max_idx;
    *integral = total_integral;
    *psd_val = Ql > 0 ? 1.0f - (float)(Qs / Ql) : 0.0f;
}

bool DetectPileUp(int16_t *buff) {
    int peak_count = 0;              // Number of detected peaks
    int samples_since_last_peak = MIN_PEAK_SEPARATION + 1;  // Reset counter
    bool in_peak = false;            // Track if we're in a peak

    // Single pass through the buffer
    for (int i = 1; i < DATA_SIZE; i++) {
	
        int diff = buff[i] - buff[i - 1];  // On-the-fly derivative

        // Detect peak start based on polarity
        if ((POLARITY == 1 && diff > PILEUP_THR) || (POLARITY == -1 && diff < -PILEUP_THR)) {
            if (!in_peak && samples_since_last_peak >= MIN_PEAK_SEPARATION) {
                peak_count++;
                in_peak = true;
                samples_since_last_peak = 0;
            }
        } 
        // End of peak when derivative flattens or reverses
        else if ((POLARITY == 1 && diff <= 0) || 
                 (POLARITY == -1 && diff >= 0)) {
            in_peak = false;
        }

        samples_since_last_peak++;
    }

    // Pile-up if more than one peak
    return (peak_count > 1);
}


// Fill 1D histograms
void FillHisto(TH1D *h_m_stamp, int m_stamp, TH1D *h_ampl, int ampl, TH1D *h_integral, double integral) {
    h_m_stamp->Fill(m_stamp);
    h_ampl->Fill(ampl);
    h_integral->Fill(integral);
}

// Fill 2D histograms
void FillHisto2D(TH2D *h_ampl_int, TH2D *h_psd_ampl, TH2D *h_psd_int, int ampl, double integral, float psd_val) {
    h_ampl_int->Fill(integral, ampl);
    h_psd_ampl->Fill(ampl, psd_val);
    h_psd_int->Fill(integral, psd_val);
}

void raw_single() {
    
    bool fCopy = false;
    const char* remoteHost = "111.111.11.111";
	
	
	const char* fileName = "raw_data";

	char remoteFile[120], localFile[120], output[120];
	
	sprintf(remoteFile, "/home/self-made/new_fpga/%s.bin", fileName);
	sprintf(localFile, "/home/user/Data/RedPitaya/IN/4ch/%s.bin", fileName);
	sprintf(output, "/home/user/Data/RedPitaya/OUT/%s.root", fileName);
	
	printf("%s\n%s\n%s\n", remoteFile, localFile, output);
	
    int N_CHOSEN = 13;
	
    if (fCopy) {
        // Copy Channel 0 file
        TString scpCommand = Form("sshpass -p root scp root@%s:%s %s", 
                                   remoteHost, remoteFile, localFile);
        std::cout << "Copying Channel 0 file from RedPitaya..." << std::endl;
        int returnCode = gSystem->Exec(scpCommand);
        if (returnCode != 0) {
            std::cerr << "Error: Failed to copy Channel 0 file!" << std::endl;
            return;
        }

    }
    
    const int window_size = 128;
    const int trace_bytes = (1 + window_size) * 8; // Header + 128 samples (64-bit each)
    
    // Open both channel files
    ifstream file(localFile, ios::binary);
        
    if (!file) {
        cout << "Error: Cannot open " << localFile << endl;
        return;
    }
   		
    // Histograms for accumulated traces
    TH2D *h_traces = new TH2D("h_traces", "CH0 Accumulated Traces;Sample Index;ADC Value", 128, 0, 128, 8192*2, -8192, 8192);
   
	TH1D *h_trace_example = new TH1D("h_trace_example", "CH0 Trace Example;Sample Index;ADC Value", 128, 0, 128);
       
    // Amplitude histograms (peak finding)
    TH1D *h_ampl = new TH1D("h_ampl", "h_ampl;ADC Counts;Events", H_AMPL_NBINS, 0, V_MAX);
	TH1D *h_integral = new TH1D("h_integral", "h_integral;Channels;Counts", H_INT_NBINS, 0, H_INT_MAX[0]);
	
	TH1D *h_m_stamp = new TH1D("h_m_stamp", "Peak Position;Bins;Counts", H_TRACE_SAMPLES, 0, H_TRACE_SAMPLES);
	
    TH2D *h_psd_ampl = new TH2D("h_psd_ampl", "PSD vs Amplitude;Amplitude;PSD", H_AMPL_NBINS, 0, H_AMPL_NBINS, H_PSD_NBINS, -1.0, 1.0);
		
		
	TH2D *h_ampl_int = new TH2D("h_ampl_int", "Amplitude vs Integral;Integral;Amplitude", H_INT_NBINS, 0, H_INT_MAX[0], H_AMPL_NBINS, 0, H_AMPL_NBINS);
    TH2D *h_psd_int = new TH2D("h_psd_int", "PSD vs Integral;Integral;PSD", H_INT_NBINS, 0, H_INT_MAX[0], H_PSD_NBINS, -1.0, 1.0);
    	
		
    
    char buffer[trace_bytes];
    int count_ch0 = 0;
    
    
    // Store events for time correlation analysis
    std::vector<uint64_t> timestamps_ch0;
    

int16_t samples[128] = {0};
uint64_t init_val[10] = {0};	
int ind_pileups = 0;
	
int ampl = 0, m_stamp = 0;
double integral = 0;
float psd_val = 0;	
	
    // Process Channel 0
    cout << "Processing Channel 0..." << endl;
    while (file.read(buffer, trace_bytes)) {
        uint64_t *ptr = (uint64_t*)buffer;
        uint64_t header = ptr[0];
        uint64_t timestamp = header & 0xFFFFFFFFFFFFULL;
        
        // Convert timestamp to seconds (125 MHz clock)
        double time_sec = (double)timestamp / 125e6;
        
        timestamps_ch0.push_back(timestamp);
        
        int16_t max_sample = -8192;
		int16_t sample = 0, s_before = 0, s_after = 0;
        	
		
        for (int i = 0; i < window_size; i++) {
            sample = (int16_t)(ptr[i+1] & 0x3FFF);
            if (sample > 8191) sample -= 16384; // Handle 14-bit two's complement
			
			if (i != 0){
				s_before = (int16_t)(ptr[i] & 0x3FFF);
            	if (s_before > 8191) s_before -= 16384; 
			}
			
			if (i != (window_size - 1)){
				s_after = (int16_t)(ptr[i+2] & 0x3FFF);
            	if (s_after > 8191) s_after -= 16384; 
			}
						
				
			if ( (sample - s_before) > 3000 &&  (sample - s_after) > 3000){
				if (count_ch0 > 300 && count_ch0 < 400)
					printf("--Fliped Event[%d] \n", count_ch0);
				sample = sample &~ 0x1000;
			}
						
            samples[i] = sample;
				
						
						
            if (sample > max_sample) max_sample = sample;
			
			
        }
		
		bool f_pileup = DetectPileUp(samples);
		if (f_pileup) ind_pileups++;
			
		//if (count_ch0 > 380 && count_ch0 < 390)
		//	printf("Event[%d] PileUp: %s \n", count_ch0, f_pileup ? "true" : "false" );
		
		
		CutBaseLine(samples);
		CalcParams(samples, &m_stamp, &ampl, &integral, &psd_val);
		
		FillHisto(h_m_stamp, m_stamp, h_ampl, ampl, h_integral, integral);
        FillHisto2D(h_ampl_int, h_psd_ampl, h_psd_int, ampl, integral, psd_val);
		
		for (int i = 0; i < window_size; i++) {
			h_traces->Fill(i, samples[i]);
		
			if (count_ch0 == N_CHOSEN)
				h_trace_example->SetBinContent(i, samples[i]);
		}
		        
        
        //if (count_ch0 > 300 && count_ch0 < 400) {
            //printf("CH0 Event[%d] Timestamp: %lu Samples[0]: %d %d %d %d %d %d %d %d %d %d \n", count_ch0, timestamp, samples[0][0], samples[0][1], samples[0][2],
			//	  samples[0][3], samples[0][4], samples[0][5], samples[0][6], samples[0][7], samples[0][8], samples[0][9]);
		//	printf("CH0 Event[%d] Timestamp: %lu Samples[27-47]:", count_ch0, timestamp);
		//	for (int j = 27; j<47; j++) printf(" %d", samples[j]);
		//	printf("\n");	
		//				
        //}
		
		
        count_ch0++;
    }

    printf(" Total events %d Pile-Ups : %d \n", count_ch0, ind_pileups);

        
    TCanvas *can = new TCanvas("can", "RedPitaya DAQ Canvas", 1600, 800);
    can->Divide(3, 3);
	
	   
    can->cd(1);
    h_m_stamp->Draw("HIST");

    can->cd(2);
    h_ampl->Draw("HIST");

    can->cd(3);
    h_integral->Draw("HIST");

    can->cd(4);
    h_ampl_int->Draw("COLZ");
	
    can->cd(5);
	h_psd_ampl->Draw("COLZ");

    can->cd(6);
    h_psd_int->Draw("COLZ");

    can->cd(7);
    h_trace_example->Draw("HIST");
	
	can->cd(8);
    h_traces->Draw("COLZ");
    
    gPad->SetLogz();
    
    TFile *f_out = new TFile(output, "RECREATE");
	f_out->cd();
	can->Write("6050");
	
	f_out->Write();
	f_out->Close();	
	
	
}
