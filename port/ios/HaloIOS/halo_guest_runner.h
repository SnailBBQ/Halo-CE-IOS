#ifndef HALO_GUEST_RUNNER_H
#define HALO_GUEST_RUNNER_H

int halo_ios_run_full_guest(void (^line)(const char *text));

/* SDL gamepad button index; called by the native menu controls. */
void halo_ios_menu_button(int button, int pressed);
void halo_ios_menu_reset(void);

#endif
