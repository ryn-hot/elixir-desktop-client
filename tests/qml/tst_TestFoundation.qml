import QtQuick
import QtTest

TestCase {
    name: "TestFoundation"

    Item {
        id: subject
        property string mode: "idle"
        property int generation: 0
        signal completed(int generation)

        function transition(nextMode) {
            mode = nextMode
            generation += 1
            completed(generation)
        }
    }

    SignalSpy {
        id: completedSpy
        target: subject
        signalName: "completed"
    }

    function init() {
        subject.mode = "idle"
        subject.generation = 0
        completedSpy.clear()
    }

    function test_qml_runner_observes_state_and_signals() {
        subject.transition("loading")
        compare(subject.mode, "loading")
        compare(subject.generation, 1)
        compare(completedSpy.count, 1)
        compare(completedSpy.signalArguments[0][0], 1)
    }

    function test_data_driven_long_text_is_preserved() {
        const value = "Live provider status with deterministic multilingual-safe text"
        subject.mode = value
        compare(subject.mode, value)
    }
}
