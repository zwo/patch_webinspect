//
//  main.m

#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>

#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach/vm_map.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <sys/types.h>
#include <mach-o/dyld.h>
#include <sys/proc_info.h>
#include <libproc.h>
#include <sys/sysctl.h>


NSArray* matchStringToRegexString(NSString *string, NSString *regexStr)
{
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexStr options:NSRegularExpressionCaseInsensitive error:nil];
    
    NSArray * matches = [regex matchesInString:string options:0 range:NSMakeRange(0, [string length])];
    
    
    NSMutableArray *array = [NSMutableArray array];
    
    for (NSTextCheckingResult *match in matches) {
        
        for (int i = 0; i < [match numberOfRanges]; i++) {
            NSString *component = [string substringWithRange:[match rangeAtIndex:i]];
            
            [array addObject:component];
            
        }
        
    }
    
    return array;
}

pid_t getProcessByName(const char *name)
{
    int procCnt = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    pid_t pids[1024];
    memset(pids, 0, sizeof pids);
    proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pids));
    
    for (int i = 0; i < procCnt; i++)
    {
        if (!pids[i]) continue;
        char curPath[PROC_PIDPATHINFO_MAXSIZE];
        char curName[PROC_PIDPATHINFO_MAXSIZE];
        memset(curPath, 0, sizeof curPath);
        proc_pidpath(pids[i], curPath, sizeof curPath);
        unsigned long len = strlen(curPath);
        if (len)
        {
            unsigned long pos = len;
            while (pos && curPath[pos] != '/') --pos;
            strcpy(curName, curPath + pos + 1);
            if (!strcmp(curName, name))
            {
                return pids[i];
            }
        }
    }
    return 0;
}

void patch_mem(task_t task, uint64_t address, mach_vm_size_t size, unsigned short original_mem,unsigned short patched_mem)
{
    fprintf(stdout, "patch memory at address 0x%llx\n", address);
    vm_offset_t data;
    mach_msg_type_number_t dataCnt;
    kern_return_t ret;
    ret = mach_vm_read(task, address, size, &data, &dataCnt);
    if (ret != KERN_SUCCESS)
    {
        fprintf(stderr, "can't read memory\n");
        return;
    }
    unsigned int *ptr=(unsigned int *)data;
    if (*ptr == original_mem)
    {
        fprintf(stdout, "Correct process version! Prepare to patch\n");
        ret = mach_vm_protect(task,address,size,FALSE ,VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE);
        if (ret != KERN_SUCCESS)
        {
            fprintf (stderr, "Unable to change protect mode: %s. Cannot continue!\n", mach_error_string(ret));
            return;
        }
        ret = mach_vm_write(task, address, (vm_offset_t)&patched_mem, (mach_msg_type_number_t)size);
        if (ret != KERN_SUCCESS)
        {
            fprintf (stderr, "Unable to change protect mode: %s. Cannot continue!\n", mach_error_string(ret));
            return;
        }
        mach_vm_deallocate(mach_task_self(), data, dataCnt);
        mach_vm_read(task, address, size, &data, &dataCnt);
        ptr=(unsigned int *)data;
        if (*ptr == patched_mem)
        {
            fprintf(stdout, "Patch Successfull!\n");
        }else{
            fprintf(stderr, "Not patched :(\n");
        }
        mach_vm_deallocate(mach_task_self(), data, dataCnt);
    }else if (*ptr == patched_mem) {
        fprintf(stdout, "Already patched\n");
        mach_vm_deallocate(mach_task_self(), data, dataCnt);
    }else{
        fprintf(stderr, "Incorrect version of process or ASLR Offset\n");
        mach_vm_deallocate(mach_task_self(), data, dataCnt);
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        uid_t uid = getuid();
        if (uid != 0)
        {
            fprintf(stderr, "Should be run as root to patch webinspectord!\n");
            return -1;
        }
        pid_t webinspectord_pid = getProcessByName("webinspectord");
        if (!webinspectord_pid)
        {
            fprintf(stderr, "Error: webinspectord not running, start some app to reload webinspectord\n");
            return -1;
        }
        fprintf(stdout, "webinspectord's pid is %d\n", webinspectord_pid);
        task_t remoteTask;
        mach_error_t kr = 0;
        kr = task_for_pid(mach_task_self(), webinspectord_pid, &remoteTask);
        if (kr != KERN_SUCCESS) {
            fprintf (stderr, "Unable to call task_for_pid on pid %d: %s. Cannot continue!\n",webinspectord_pid, mach_error_string(kr));
            return (-1);
        }
        NSTask *task=[NSTask new];
        task.launchPath = @"/bin/bash";
        task.arguments=@[@"-c", [NSString stringWithFormat:@"vmmap %d", webinspectord_pid]];
        NSPipe *pipe;
        pipe = [NSPipe pipe];
        [task setStandardOutput: pipe];
        NSFileHandle *file = [pipe fileHandleForReading];
        [task launch];
        
        NSData *data = [file readDataToEndOfFile];
        
        NSString *outputString = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
        NSArray *lines=[outputString componentsSeparatedByString:@"\n"];
        uint64_t aslr_offset=0;
        for (NSString *line in lines) {
            if ([line rangeOfString:@"WebInspector."].location != NSNotFound) {
                NSString *regStr=@"\\b0*7ff\\w+\\b";
                NSArray *arr=matchStringToRegexString(line, regStr);
                NSString *offsetStr=arr[0];
                NSScanner *scanner = [NSScanner scannerWithString:offsetStr];
                [scanner scanHexLongLong:&aslr_offset];
                break;
            }
        }
        if (aslr_offset == 0) {
            fprintf(stderr, "WebInspector's memory offset can't be figured out!\n");
        }
       patch_mem(remoteTask, aslr_offset+0x81974, sizeof(unsigned short), 0xc084, 0xdb84);
    }
    return 0;
}
