#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <pthread.h>
#include <string.h>
#include <time.h>

// Configuration

#define N_CH 4
#define ACQ_DURATION 3600
#define THRESHOLD_0 200
#define THRESHOLD_1 500
#define THRESHOLD_2 100
#define THRESHOLD_3 50

// Memory map addresses
#define HUB_ADDR     0x40000000
#define HUB_STS_ADDR 0x41000000
#define DMA0_ADDR    0x40020000
#define DMA1_ADDR    0x40030000
#define DMA2_ADDR    0x40040000
#define DMA3_ADDR    0x40050000

//#define DDR0_BASE    0x1E000000
//#define DDR1_BASE    0x1F000000

#define DDR0_BASE    0x18000000
#define DDR1_BASE    0x1A000000
#define DDR2_BASE    0x1C000000
#define DDR3_BASE    0x1E000000

// Data structure
#define WORDS_PER_EVENT   1025
#define FULL_PACKET_SIZE  (WORDS_PER_EVENT * 8)
#define WINDOW_START 236 //Trigger @256 in FPGA
#define WINDOW_SIZE  128
#define SAVED_TRACE_SIZE ((1 + WINDOW_SIZE) * 8)
#define BATCH_COUNT  10 //500
#define BATCH_SIZE   (SAVED_TRACE_SIZE * BATCH_COUNT)

// DMA registers
#define S2MM_CONTROL 0x30
#define S2MM_STATUS  0x34
#define S2MM_DEST    0x48
#define S2MM_LENGTH  0x58

typedef struct {
    uint8_t data[BATCH_SIZE];
    int ready_to_write;
} DoubleBuffer;

// Buffers for all 4 channels
DoubleBuffer buffers_ch[4][2];
int current_fill[4] = {0};
int batch_idx[4] = {0};

pthread_mutex_t mutex[4] = {
    PTHREAD_MUTEX_INITIALIZER,
    PTHREAD_MUTEX_INITIALIZER,
    PTHREAD_MUTEX_INITIALIZER,
    PTHREAD_MUTEX_INITIALIZER
};

pthread_cond_t cond[4] = {
    PTHREAD_COND_INITIALIZER,
    PTHREAD_COND_INITIALIZER,
    PTHREAD_COND_INITIALIZER,
    PTHREAD_COND_INITIALIZER
};

int keep_running = 1;
uint32_t total_events[4] = {0};

void reset_dma(volatile uint32_t *dma) {
    dma[S2MM_CONTROL/4] = 0x0004;
    while(dma[S2MM_CONTROL/4] & 0x0004);
    dma[S2MM_STATUS/4]  = 0x7000;
}

// Generic writer thread
void* writer_thread(void* arg) {
    int ch = *(int*)arg;
    char filename[64];
    snprintf(filename, sizeof(filename), "raw_data_ch%d.bin", ch);
    
    FILE *f = fopen(filename, "wb");
    if (!f) {
        fprintf(stderr, "ERROR: Cannot open %s\n", filename);
        return NULL;
    }

    int write_idx = 0;
    while (keep_running || buffers_ch[ch][write_idx].ready_to_write) {
        pthread_mutex_lock(&mutex[ch]);
        while (!buffers_ch[ch][write_idx].ready_to_write && keep_running) {
            pthread_cond_wait(&cond[ch], &mutex[ch]);
        }
        pthread_mutex_unlock(&mutex[ch]);

        if (buffers_ch[ch][write_idx].ready_to_write) {
            fwrite(buffers_ch[ch][write_idx].data, 1, BATCH_SIZE, f);
            buffers_ch[ch][write_idx].ready_to_write = 0;
            write_idx = (write_idx + 1) % 2;
        }
    }
    fclose(f);
    return NULL;
}

int main() {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("Cannot open /dev/mem");
        return -1;
    }
    
    // Memory map all addresses
    volatile uint32_t *hub_cfg = mmap(NULL, 65536, PROT_READ|PROT_WRITE, MAP_SHARED, fd, HUB_ADDR);
    volatile uint32_t *hub_sts = mmap(NULL, 65536, PROT_READ|PROT_WRITE, MAP_SHARED, fd, HUB_STS_ADDR);
    
    volatile uint32_t *dma[4];
    dma[0] = mmap(NULL, 65536, PROT_READ|PROT_WRITE, MAP_SHARED, fd, DMA0_ADDR);
    dma[1] = mmap(NULL, 65536, PROT_READ|PROT_WRITE, MAP_SHARED, fd, DMA1_ADDR);
    dma[2] = mmap(NULL, 65536, PROT_READ|PROT_WRITE, MAP_SHARED, fd, DMA2_ADDR);
    dma[3] = mmap(NULL, 65536, PROT_READ|PROT_WRITE, MAP_SHARED, fd, DMA3_ADDR);
    
    uint32_t ddr_bases[4] = {DDR0_BASE, DDR1_BASE, DDR2_BASE, DDR3_BASE};
    volatile uint64_t *ddr_src[4];
    for (int i = 0; i < N_CH; i++) {
        ddr_src[i] = mmap(NULL, FULL_PACKET_SIZE, PROT_READ|PROT_WRITE, MAP_SHARED, fd, ddr_bases[i]);
    }

    // Check mmaps
    if (hub_cfg == MAP_FAILED || hub_sts == MAP_FAILED) {
        perror("mmap failed");
        close(fd);
        return -1;
    }
    for (int i = 0; i < N_CH; i++) {
        if (dma[i] == MAP_FAILED || ddr_src[i] == MAP_FAILED) {
            perror("mmap failed");
            close(fd);
            return -1;
        }
    }

    // Set thresholds (CFG[0]=ARM, [14:1]=TH0, [28:15]=TH1, [42:29]=TH2, [56:43]=TH3)
    uint64_t cfg = 0;
    cfg |= ((uint64_t)0 << 0); // ARM = 0 
    cfg |= ((uint64_t)(THRESHOLD_0 & 0x3FFF) << 1);
    cfg |= ((uint64_t)(THRESHOLD_1 & 0x3FFF) << 15);
    cfg |= ((uint64_t)(THRESHOLD_2 & 0x3FFF) << 29);
    cfg |= ((uint64_t)(THRESHOLD_2 & 0x3FFF) << 43);

    hub_cfg[0] = (uint32_t)(cfg & 0x0FFFFFFF);
    hub_cfg[1] = (uint32_t)(cfg >> 32);

    printf("DEBUG: Configuration set:\n");
    printf("  hub_cfg[0] = 0x%08X\n", hub_cfg[0]);
    printf("  hub_cfg[1] = 0x%08X\n", hub_cfg[1]);

    // Initialize buffers
    for (int i = 0; i < N_CH; i++) {
        memset(buffers_ch[i], 0, sizeof(buffers_ch[i]));
    }

    // Start writer threads
    pthread_t threads[4];
    int thread_args[4] = {0, 1, 2, 3};
    for (int i = 0; i < N_CH; i++) {
        pthread_create(&threads[i], NULL, writer_thread, &thread_args[i]);
    }

    printf("=======================================================\n");
    printf("4-Channel DAQ System Started\n");
    printf("=======================================================\n");
    printf("Duration: %d seconds\n", ACQ_DURATION);
    printf("Thresholds: CH0=%d, CH1=%d, CH2=%d, CH3=%d\n", 
           THRESHOLD_0, THRESHOLD_1, THRESHOLD_2, THRESHOLD_3);
    printf("Window: Start=%d, Size=%d samples\n", WINDOW_START, WINDOW_SIZE);
    printf("=======================================================\n\n");

    // Prepare all DMAs
    for (int i = 0; i < N_CH; i++) {
        reset_dma(dma[i]);
        dma[i][S2MM_DEST/4] = ddr_bases[i];
        dma[i][S2MM_CONTROL/4] = 0x0001;
        dma[i][S2MM_LENGTH/4] = FULL_PACKET_SIZE;
    }

    // Arm FPGA
    hub_cfg[0] |= 1;

    time_t start_time = time(NULL);
    time_t last_report_time = start_time;
    uint32_t last_total[4] = {0};

    while (time(NULL) - start_time < ACQ_DURATION) {
        // Poll all 4 DMAs
        for (int ch = 0; ch < N_CH; ch++) {
           // if (ch ==0){
            uint32_t status = dma[ch][S2MM_STATUS/4];
            
            if (status & 0x1000) {  // IOC_Irq
                uint64_t header = ddr_src[ch][0];
                uint64_t ts = header & 0xFFFFFFFFFFFFULL;
                
                if (ts >= 100000) {
                    total_events[ch]++;
                    
                    uint8_t *dst = &buffers_ch[ch][current_fill[ch]].data[batch_idx[ch] * SAVED_TRACE_SIZE];
                    memcpy(dst, (void*)&ddr_src[ch][0], 8);
                    memcpy(dst + 8, (void*)&ddr_src[ch][1 + WINDOW_START], WINDOW_SIZE * 8);
                    
                    batch_idx[ch]++;
                    
                    if (batch_idx[ch] >= BATCH_COUNT) {
                        pthread_mutex_lock(&mutex[ch]);
                        buffers_ch[ch][current_fill[ch]].ready_to_write = 1;
                        current_fill[ch] = (current_fill[ch] + 1) % 2;
                        batch_idx[ch] = 0;
                        pthread_cond_signal(&cond[ch]);
                        pthread_mutex_unlock(&mutex[ch]);
                    }
                }
                
                // Re-arm DMA (CRITICAL: LENGTH first, STATUS last)
                dma[ch][S2MM_LENGTH/4] = FULL_PACKET_SIZE;
                dma[ch][S2MM_STATUS/4] = 0x7000;
            }
           // }// channels if
        }

        // Reporting
        time_t now = time(NULL);
        if (now > last_report_time) {
            uint32_t rates[4];
            for (int i = 0; i < 4; i++) {
                rates[i] = total_events[i] - last_total[i];
                last_total[i] = total_events[i];
            }
            
            // Parse status register
            uint32_t busy = hub_sts[0] & 0xF;
            uint32_t hw_f[4];
            hw_f[0] = (hub_sts[0] >> 4) & 0x0FFFFFFF;
            hw_f[1] = (hub_sts[1] >> 0) & 0x0FFFFFFF;
	    	hw_f[2] = ((hub_sts[1] >> 28) & 0xF) | (((hub_sts[2] >> 0) & 0xFFFFFF) << 4);
	    	hw_f[3] = ((hub_sts[2] >> 24) & 0xFF) | (((hub_sts[3] >> 0) & 0xFFFFF) << 8);
            printf("\rT:%ld/%ds | SW[%u,%u,%u,%u] Hz | HW[%u,%u,%u,%u] | Total[%u,%u,%u,%u] | B[%X]",
                   now - start_time, ACQ_DURATION,
                   rates[0], rates[1], rates[2], rates[3],
                   hw_f[0], hw_f[1], hw_f[2], hw_f[3],
                   total_events[0], total_events[1], total_events[2], total_events[3],
                   busy);
            fflush(stdout);
            last_report_time = now;
        }
        
        usleep(100);
    }


    printf("\n\n=======================================================\n");
    printf("Measurement complete. Cleaning up...\n");
    printf("=======================================================\n");
    
    hub_cfg[0] &= ~1;
    keep_running = 0;
    
    for (int i = 0; i < N_CH; i++) {
        pthread_cond_signal(&cond[i]);
        pthread_join(threads[i], NULL);
    }

    printf("Final Statistics:\n");
    for (int i = 0; i < N_CH; i++) {
        printf("  Channel %d: %u events\n", i, total_events[i]);
    }
    printf("  Total:     %u events\n", 
           total_events[0] + total_events[1] + total_events[2] + total_events[3]);
    printf("=======================================================\n");

    // Cleanup
    munmap((void*)hub_cfg, 65536);
    munmap((void*)hub_sts, 65536);
    for (int i = 0; i < N_CH; i++) {
        munmap((void*)dma[i], 65536);
        munmap((void*)ddr_src[i], FULL_PACKET_SIZE);
    }
    close(fd);
    
    return 0;
}
