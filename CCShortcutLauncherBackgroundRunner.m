#import "CCShortcutLauncherBackgroundRunner.h"

#import <dlfcn.h>

@protocol CSLPrivateWorkflowRunner <NSObject>
- (instancetype)initWithWorkflowIdentifier:(NSString *)workflowIdentifier;
- (void)start;
- (BOOL)isRunning;
@end

static id<CSLPrivateWorkflowRunner> CSLActiveRunner;
static NSUInteger CSLRunnerGeneration;

static BOOL CSLLoadRunnerFrameworks(void) {
    static dispatch_once_t onceToken;
    static BOOL loaded = NO;

    dispatch_once(&onceToken, ^{
        void *workflowKit = dlopen(
            "/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit",
            RTLD_LAZY | RTLD_LOCAL
        );
        if (workflowKit == NULL) {
            const char *error = dlerror();
            NSLog(@"[CCShortcutLauncher][Background] FRAMEWORK_LOAD_FAILED framework=WorkflowKit error=%s",
                  error != NULL ? error : "unknown");
            return;
        }

        void *voiceShortcutClient = dlopen(
            "/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/VoiceShortcutClient",
            RTLD_LAZY | RTLD_LOCAL
        );
        if (voiceShortcutClient == NULL) {
            const char *error = dlerror();
            NSLog(@"[CCShortcutLauncher][Background] FRAMEWORK_LOAD_FAILED framework=VoiceShortcutClient error=%s",
                  error != NULL ? error : "unknown");
            return;
        }

        loaded = YES;
    });

    return loaded;
}

static void CSLPollRunner(
    id<CSLPrivateWorkflowRunner> runner,
    NSString *shortcutName,
    NSUInteger generation,
    NSUInteger attempt,
    BOOL observedRunning
) {
    NSTimeInterval pollInterval = attempt < 120 ? 0.5 : 5.0;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(pollInterval * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            if (generation != CSLRunnerGeneration || CSLActiveRunner != runner) {
                return;
            }

            BOOL running = NO;
            @try {
                running = [runner isRunning];
            } @catch (NSException *exception) {
                NSLog(@"[CCShortcutLauncher][Background] STATUS_EXCEPTION name=\"%@\" exception=%@ reason=%@",
                      shortcutName,
                      exception.name,
                      exception.reason);
                CSLActiveRunner = nil;
                return;
            }

            BOOL hasObservedRunning = observedRunning || running;
            if (running && !observedRunning) {
                NSLog(@"[CCShortcutLauncher][Background] RUNNING name=\"%@\"",
                      shortcutName);
            }

            if (!running && observedRunning) {
                NSLog(@"[CCShortcutLauncher][Background] FINISHED_OBSERVED name=\"%@\"",
                      shortcutName);
                CSLActiveRunner = nil;
                return;
            }

            if (!running && !observedRunning && attempt >= 5) {
                NSLog(@"[CCShortcutLauncher][Background] FINISHED_OR_NOT_STARTED name=\"%@\"",
                      shortcutName);
                CSLActiveRunner = nil;
                return;
            }

            if (attempt == 119 && running) {
                NSLog(@"[CCShortcutLauncher][Background] STILL_RUNNING name=\"%@\"; reducing status poll frequency",
                      shortcutName);
            }

            CSLPollRunner(
                runner,
                shortcutName,
                generation,
                attempt + 1,
                hasObservedRunning
            );
        }
    );
}

CSLBackgroundStartResult CSLStartBackgroundShortcutNamed(
    NSString *shortcutName,
    NSString *workflowIdentifier
) {
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:workflowIdentifier];
    if (uuid == nil) {
        NSLog(@"[CCShortcutLauncher][Background] WORKFLOW_ID_INVALID name=\"%@\" value=\"%@\"",
              shortcutName,
              workflowIdentifier);
        return CSLBackgroundStartResultPreflightFailed;
    }
    NSString *normalizedIdentifier = uuid.UUIDString;

    if (!CSLLoadRunnerFrameworks()) {
        return CSLBackgroundStartResultPreflightFailed;
    }

    if (CSLActiveRunner != nil) {
        BOOL running = NO;
        @try {
            running = [CSLActiveRunner isRunning];
        } @catch (__unused NSException *exception) {
            CSLActiveRunner = nil;
        }

        if (running) {
            NSLog(@"[CCShortcutLauncher][Background] ALREADY_RUNNING requestedName=\"%@\"",
                  shortcutName);
            return CSLBackgroundStartResultAlreadyRunning;
        }
        CSLActiveRunner = nil;
    }

    Class runnerClass = NSClassFromString(@"WFSpringBoardWorkflowRunnerClient");
    SEL initializer = NSSelectorFromString(@"initWithWorkflowIdentifier:");
    if (runnerClass == Nil || ![runnerClass instancesRespondToSelector:initializer]) {
        NSLog(@"[CCShortcutLauncher][Background] RUNNER_UNAVAILABLE class=WFSpringBoardWorkflowRunnerClient");
        return CSLBackgroundStartResultPreflightFailed;
    }

    @try {
        id<CSLPrivateWorkflowRunner> runner =
            [(id<CSLPrivateWorkflowRunner>)[runnerClass alloc]
                initWithWorkflowIdentifier:normalizedIdentifier];
        if (runner == nil) {
            NSLog(@"[CCShortcutLauncher][Background] RUNNER_INIT_FAILED name=\"%@\" workflowID=%@",
                  shortcutName,
                  normalizedIdentifier);
            return CSLBackgroundStartResultPreflightFailed;
        }

        CSLActiveRunner = runner;
        NSUInteger generation = ++CSLRunnerGeneration;
        [runner start];
        NSLog(@"[CCShortcutLauncher][Background] START_SENT name=\"%@\" workflowID=%@",
              shortcutName,
              normalizedIdentifier);
        CSLPollRunner(runner, shortcutName, generation, 0, NO);
        return CSLBackgroundStartResultSubmitted;
    } @catch (NSException *exception) {
        NSLog(@"[CCShortcutLauncher][Background] START_EXCEPTION name=\"%@\" exception=%@ reason=%@",
              shortcutName,
              exception.name,
              exception.reason);
        CSLActiveRunner = nil;
        return CSLBackgroundStartResultPreflightFailed;
    }
}
