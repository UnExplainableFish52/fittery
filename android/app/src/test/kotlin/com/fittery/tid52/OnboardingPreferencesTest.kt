package com.fittery.tid52

import android.app.Application
import android.content.Context
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE, application = Application::class)
class OnboardingPreferencesTest {
    private lateinit var context: Context
    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("onboarding", Context.MODE_PRIVATE).edit().clear().commit()
    }

    @Test fun freshInstallShowsTheTutorialUntilItIsExplicitlyCompleted() {
        val initial = OnboardingPreferences(context).snapshot()
        assertEquals(false, initial["onboardingCompleted"])
        assertEquals(true, initial["showOnboardingOnLaunch"])
        assertEquals(initial, OnboardingPreferences(context).snapshot())
    }

    @Test fun completingWithDontShowAgainSurvivesARecreatedPreferencesObject() {
        OnboardingPreferences(context).complete(false)
        val reopened = OnboardingPreferences(context).snapshot()
        assertEquals(true, reopened["onboardingCompleted"])
        assertEquals(false, reopened["showOnboardingOnLaunch"])
    }

    @Test fun replayCanEnableFutureLaunchesWithoutResettingCompletionOrAlarmChoices() {
        val alarms = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        val original = "{\"chargeLimit\":85,\"toneName\":\"My song.mp3\"}"
        alarms.edit().putString("values", original).commit()
        val preferences = OnboardingPreferences(context)
        preferences.complete(false)
        preferences.complete(true)
        val reopened = OnboardingPreferences(context).snapshot()
        assertEquals(true, reopened["onboardingCompleted"])
        assertEquals(true, reopened["showOnboardingOnLaunch"])
        assertEquals(original, alarms.getString("values", null))
    }
}
